/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* Adapted for pipeline-FPU difftest (spike as REF).
* Built against the prebuilt riscv-isa-sim static libs under $(NEMU_HOME)/tools/spike-diff
* (read-only). Only this FPU project is modified.
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "mmu.h"
#include "sim.h"
#include <common.h>

#ifndef __EXPORT
#define __EXPORT __attribute__((visibility("default")))
#endif

enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };

#define NR_GPR MUXDEF(CONFIG_RVE, 16, 32)
#define NR_FPR 32

static std::vector<std::pair<reg_t, abstract_device_t*>> difftest_plugin_devices;
static std::vector<std::string> difftest_htif_args;
static std::vector<std::pair<reg_t, mem_t*>> difftest_mem(
    1, std::make_pair(reg_t(DRAM_BASE), new mem_t(CONFIG_MSIZE)));
static debug_module_config_t difftest_dm_config = {
  .progbufsize = 2,
  .max_sba_data_width = 0,
  .require_authentication = false,
  .abstract_rti = 0,
  .support_hasel = true,
  .support_abstract_csr_access = true,
  .support_abstract_fpr_access = true,
  .support_haltgroups = true,
  .support_impebreak = true
};

typedef struct{
  word_t mcause;//存放异常原因
  vaddr_t mepc;//存放触发异常的地址PC
  word_t mstatus;//存放当前状态
  word_t mtvec;//存放异常向量表地址
}riscv32_CSRs;

struct diff_context_t {
  word_t gpr[MUXDEF(CONFIG_RVE, 16, 32)];
  word_t pc;
  riscv32_CSRs csr;
  word_t fpr[NR_FPR];
  word_t fcsr;
};

static sim_t* s = NULL;
static processor_t *p = NULL;
static state_t *state = NULL;

void sim_t::diff_init(int port) {
  p = get_core("0");
  state = p->get_state();
}

void sim_t::diff_step(uint64_t n) {
  step(n);
}

void sim_t::diff_get_regs(void* diff_context) {
  struct diff_context_t* ctx = (struct diff_context_t*)diff_context;
  for (int i = 0; i < NR_GPR; i++) {
    ctx->gpr[i] = state->XPR[i];
  }
  ctx->pc = state->pc;
  for (int i = 0; i < NR_FPR; i++) {
    ctx->fpr[i] = (uint32_t)state->FPR[i].v[0];
  }
  ctx->fcsr = (uint32_t)((state->frm->read() << 5) | state->fflags->read());
}

void sim_t::diff_set_regs(void* diff_context) {
  struct diff_context_t* ctx = (struct diff_context_t*)diff_context;
  for (int i = 0; i < NR_GPR; i++) {
    state->XPR.write(i, (sword_t)ctx->gpr[i]);
  }
  state->pc = ctx->pc;
  for (int i = 0; i < NR_FPR; i++) {
    freg_t t;
    t.v[0] = ctx->fpr[i];
    t.v[1] = 0; // RV32 无 NaN-boxing 要求, 高 64bit 置 0
    state->FPR.write(i, t);
  }
  // Spike 复位时 mstatus.FS=Off, float_csr_t::unlogged_write 会调用
  // dirty_fp_state -> dirty(SSTATUS_FS) -> abort() 当 FS=Off 时
  // 先将 mstatus.FS 设为 Dirty(3<<13) 再写 float CSR
  const reg_t SSTATUS_FS_DIRTY = 3UL << 13;
  if (!(state->mstatus->read() & SSTATUS_FS_DIRTY)) {
    state->mstatus->write(state->mstatus->read() | SSTATUS_FS_DIRTY);
  }
  state->frm->write(ctx->fcsr >> 5);
  state->fflags->write(ctx->fcsr & 0x1f);
}

void sim_t::diff_memcpy(reg_t dest, void* src, size_t n) {
  mmu_t* mmu = p->get_mmu();
  for (size_t i = 0; i < n; i++) {
    mmu->store<uint8_t>(dest+i, *((uint8_t*)src+i));
  }
}

extern "C" {

__EXPORT void difftest_memcpy(paddr_t addr, void *buf, size_t n, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    s->diff_memcpy(addr, buf, n);
  } else {
    assert(0);
  }
}

__EXPORT void difftest_regcpy(void* dut, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    s->diff_set_regs(dut);
  } else {
    s->diff_get_regs(dut);
  }
}

__EXPORT void difftest_exec(uint64_t n) {
  s->diff_step(n);
}

__EXPORT void difftest_init(int port) {
  difftest_htif_args.push_back("");
  const char *isa = "RV" MUXDEF(CONFIG_RV64, "64", "32") MUXDEF(CONFIG_RVE, "E", "I") "MAFDC";
  cfg_t cfg(/*default_initrd_bounds=*/std::make_pair((reg_t)0, (reg_t)0),
            /*default_bootargs=*/nullptr,
            /*default_isa=*/isa,
            /*default_priv=*/DEFAULT_PRIV,
            /*default_varch=*/DEFAULT_VARCH,
            /*default_misaligned=*/false,
            /*default_endianness*/endianness_little,
            /*default_pmpregions=*/16,
            /*default_mem_layout=*/std::vector<mem_cfg_t>(),
            /*default_hartids=*/std::vector<size_t>(1),
            /*default_real_time_clint=*/false,
            /*default_trigger_count=*/4);
  s = new sim_t(&cfg, false,
      difftest_mem, difftest_plugin_devices, difftest_htif_args,
      difftest_dm_config, nullptr, false, NULL,
      false,
      NULL,
      true);
  s->diff_init(port);
}

__EXPORT void difftest_raise_intr(uint64_t NO) {
  trap_t t(NO);
  p->take_trap_public(t, state->pc);
}

}