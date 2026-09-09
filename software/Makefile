# RV32IMF 软件测试环境 Makefile
#
#   make test TEST=add           编译 test/add.c,输出 build/test/add.bin 与反汇编 build/test/add.txt
#   make test                    编译 test/ 下所有 .c 测试
#   make asm  TEST=fmsub_b15-017 编译 asm-test/fmsub_b15/fmsub_b15-017.S,输出 build/asm-test/fmsub_b15-017.bin 与 .txt
#   make asm                     编译 asm-test/ 下所有 .S 测试(含子目录)
#   make all                     编译全部 test 与 asm 测试
#   make clean                   删除 build 目录

CROSS_COMPILE = riscv64-linux-gnu-

include RV32IMF.mk

CC       = $(CROSS_COMPILE)gcc
LD       = $(CROSS_COMPILE)ld
OBJCOPY  = $(CROSS_COMPILE)objcopy
OBJDUMP  = $(CROSS_COMPILE)objdump

BUILD_DIR   = build
INC_PATH    = include
LINK_SCRIPT = scripts/linker.ld

CFLAGS = $(COMMON_CFLAGS) -DFLEN=32 -I$(INC_PATH) -fno-pic -Wall -fno-stack-protector

# 公共运行库对象: start.S 提供入口 _start,trm.c 提供 _trm_init/halt
COMMON_OBJS = $(BUILD_DIR)/start.o $(BUILD_DIR)/trm.o

# ---- 测试源文件收集 ---------------------------------------------------------

# 根据 TEST 名定位 asm 测试源文件:
# 先在 asm-test/ 顶层找 <TEST>.S,再按前缀目录找 asm-test/<前缀>/<TEST>.S
# 例: fadd_b1-01   -> asm-test/fadd_b1-01.S
#     fmsub_b15-017 -> asm-test/fmsub_b15/fmsub_b15-017.S
asm-src = $(firstword \
  $(wildcard asm-test/$(1).S) \
  $(wildcard asm-test/$(subst -$(lastword $(subst -, ,$(1))),,$(1))/$(1).S))

ifneq ($(TEST),)
  TEST_C_SRC  := $(wildcard test/$(TEST).c)
  TEST_ASM_SRC := $(call asm-src,$(TEST))
  ifeq ($(strip $(TEST_C_SRC) $(TEST_ASM_SRC)),)
    $(error 找不到测试: $(TEST)(test/$(TEST).c 或 asm-test 下的 $(TEST).S))
  endif
endif

C_SRCS := $(if $(TEST_C_SRC),$(TEST_C_SRC),$(wildcard test/*.c))
C_BINS := $(patsubst test/%.c,$(BUILD_DIR)/test/%.bin,$(C_SRCS))

ASM_SRCS := $(if $(TEST_ASM_SRC),$(TEST_ASM_SRC),$(wildcard asm-test/*.S) $(wildcard asm-test/*/*.S))
ASM_BINS := $(addprefix $(BUILD_DIR)/asm-test/,$(addsuffix .bin,$(notdir $(basename $(ASM_SRCS)))))

# ---- 构建规则 ---------------------------------------------------------------

.PHONY: test asm all clean

test: $(C_BINS)
asm:  $(ASM_BINS)
all:  test asm

# 编译 + 链接 + 生成 bin 与反汇编 txt
# $(1): 输出目标前缀(build/test/add 等),$(2): 源文件
define MAKE_BIN
$$(subst .bin,.elf,$(1).bin): $(2) $(COMMON_OBJS) $(LINK_SCRIPT)
	@mkdir -p $$(dir $$@)
	$$(CC) $$(CFLAGS) -c $$< -o $$(subst .elf,.o,$$@)
	$$(LD) -m elf32lriscv -T $(LINK_SCRIPT) $(COMMON_OBJS) $$(subst .elf,.o,$$@) -o $$@
	$$(OBJCOPY) -O binary $$@ $$(subst .elf,.bin,$$@)
	$$(OBJDUMP) -d $$@ > $$(subst .elf,.txt,$$@)

$(1).bin: $$(subst .bin,.elf,$(1).bin)
	@true
endef

# c 测试
$(foreach s,$(C_SRCS),$(eval $(call MAKE_BIN,$(BUILD_DIR)/test/$(basename $(notdir $(s))),$(s))))

# asm 测试(输出平铺到 build/asm-test/,文件名本身已含覆盖组编号)
$(foreach s,$(ASM_SRCS),$(eval $(call MAKE_BIN,$(BUILD_DIR)/asm-test/$(basename $(notdir $(s))),$(s))))

# 公共对象
$(BUILD_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR)
