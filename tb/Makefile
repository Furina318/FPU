# tb 单元级验证 Makefile (iverilog)

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
