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
