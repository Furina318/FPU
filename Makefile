# FPU 顶层 Makefile
#
#   make cpu TEST=dummy        编译 software 测试并在 cpu 核上跑 verilator 仿真, 生成波形
#                              产物: cpu/build/(verilator 编译产物、Vysyx_25010030_npc、npc-log.txt、wave.vcd)
#   make cpu TEST=fadd_b1-01   运行 asm 测试(与 C 测试同名时优先 C 测试)
#   make cpu-clean             清理 cpu 构建产物
#   make tb                    运行 rtl 单元级验证(iverilog, 详见 tb/Makefile)

TEST ?= dummy
FRAME ?= pipeline-FPU

SOFTWARE_DIR = software
CPU_DIR      = cpu
CPU_BUILD    = $(CPU_DIR)/build

# C 测试优先, 否则按 asm 测试处理(software/Makefile 内部会校验测试名是否存在)
SW_TARGET := $(if $(wildcard $(SOFTWARE_DIR)/test/$(TEST).c),test,asm)
# software 构建产物目录: C 测试在 build/test/, asm 测试在 build/asm-test/
SW_OUT_DIR := $(if $(filter test,$(SW_TARGET)),test,asm-test)
SW_BIN     := $(SOFTWARE_DIR)/build/$(SW_OUT_DIR)/$(TEST).bin

.PHONY: cpu cpu-clean tb

cpu:
	$(MAKE) -C $(SOFTWARE_DIR) $(SW_TARGET) TEST=$(TEST)
	# BAD TRAP 时仿真器返回非零, 加 - 前缀保证波形仍被收集
	-$(MAKE) -C $(CPU_DIR) run OBJ_DIR=build diff=0 FRAME=$(FRAME) \
		ARGS="-b --log=build/npc-log.txt" \
		IMG=$(abspath $(SW_BIN))
	@mv -f $(CPU_DIR)/wave.vcd $(CPU_BUILD)/wave.vcd
	@echo "波形: $(CPU_BUILD)/wave.vcd"

cpu-clean:
	$(MAKE) -C $(CPU_DIR) clean

tb:
	$(MAKE) -C tb all
