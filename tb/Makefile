# tb 单元级验证 Makefile (iverilog)
#
#   make all    编译并运行全部单元测试(rtl/fdiv.v 未实现时自动跳过 tb_fdiv)
#   make fma    只跑 tb_fma_unit
#   make fpu    只跑 tb_fpu
#   make fdiv   只跑 tb_fdiv
#   make clean  清理 build/ 与波形

IVERILOG = iverilog
VVP      = vvp

BUILD_DIR = build
RTL_DIR   = ../rtl
RTL_SRCS  = $(wildcard $(RTL_DIR)/*.v)

IVERILOG_FLAGS = -g2012 -Wall -I$(RTL_DIR) -I.

.PHONY: all fma fpu fdiv clean

all: tb_fma_unit tb_fpu tb_quick fdiv

fma: tb_fma_unit
fpu: tb_fpu
quick: tb_quick

fdiv:
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(BUILD_DIR)/tb_fdiv.out $(RTL_SRCS) tb_fdiv.v
	$(VVP) $(BUILD_DIR)/tb_fdiv.out

tb_fma_unit tb_fpu tb_quick:
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(BUILD_DIR)/$@.out $(RTL_SRCS) $@.v
	$(VVP) $(BUILD_DIR)/$@.out

clean:
	rm -rf $(BUILD_DIR) *.vcd
