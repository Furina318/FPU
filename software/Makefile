# RV32IMF 软件测试环境 Makefile

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

.PHONY: test asm all clean

test: $(C_BINS)
asm:  $(ASM_BINS)
all:  test asm

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

$(foreach s,$(C_SRCS),$(eval $(call MAKE_BIN,$(BUILD_DIR)/test/$(basename $(notdir $(s))),$(s))))

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
