#ifndef __MODEL_TEST__
#define __MODEL_TEST__

// 本项目的模型适配:
// 程序从 start.S 的 _start 进入,经 _trm_init 调用 main,
// 再由 main 调用 rvtest_entry_point 执行测试。
// 测试结束后执行 ebreak,模拟器遇到 ebreak 指令即退出仿真。

#define TEST_CASE_1

#define XLEN __riscv_xlen
#ifdef __riscv_e
#define RVTEST_E
#endif

// 舍入模式常量(dyn 表示按 fcsr.frm 动态舍入)
// gas 的浮点指令 rm 操作数只接受符号,故用 .set 定义为汇编符号
.set rne, 0
.set rtz, 1
.set rdn, 2
.set rup, 3
.set rmm, 4
.set dyn, 7

#define RVMODEL_DATA_BEGIN  .align 4; .global begin_signature; begin_signature:
#define RVMODEL_DATA_END    .align 4; .global end_signature; end_signature:

#define RVMODEL_BOOT        // empty

// ebreak 退出仿真,若仿真器未退出则在此死循环。
// riscv-ctg 测试不定义 a0,但模拟器以 ebreak 时 a0==0 判定 GOOD TRAP,
// 故在 ebreak 前清零 a0,表示测试代码已完整执行到结束。
#define RVMODEL_HALT        \
  li a0, 0;                 \
  nop;                      \
  ebreak;                   \
halt_loop:                  \
  j halt_loop;

#define RVMODEL_IO_INIT     // empty
#define RVMODEL_IO_ASSERT_GPR_EQ(_SP, _R, _I)   // empty
#define RVMODEL_IO_ASSERT_SFPR_EQ(_SP, _F, _I)  // empty
#define RVMODEL_IO_ASSERT_DFPR_EQ(_SP, _D, _I)  // empty
#define RVMODEL_IO_WRITE_STR(ScrReg, String)    // empty

.section .text
.globl main
main:
  call rvtest_entry_point
  li a0, 0
  ret

#endif
