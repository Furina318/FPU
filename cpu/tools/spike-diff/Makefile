#***************************************************************************************
# Build riscv32-spike-so for pipeline-FPU difftest.
# Reuses the prebuilt riscv-isa-sim static libs under $(NEMU_HOME)/tools/spike-diff
# (read-only). Nothing inside the NEMU tree is modified.
#***************************************************************************************/

NEW_CORE_HOME ?= $(abspath ..)
FRAME ?= pipeline-FPU

# 使用 FPU 本地副本 (含 F 扩展指令), 构建自 $(NEMU_HOME)/tools/spike-diff/repo 源码拷贝
REPO_PATH = $(abspath repo)
REPO_BUILD_PATH = $(REPO_PATH)/build

# 使用 FPU 本地副本 (含 F 扩展指令), 构建自 $(NEMU_HOME)/tools/spike-diff/repo 源码拷贝
# 注意: pipeline 的 common.h 必须排在 spike riscv/common.h 之前
inc_dependencies = fesvr riscv disasm customext fdt softfloat spike_main spike_dasm build
INC_PATH  = -I$(NEW_CORE_HOME)/$(FRAME)/include
INC_PATH += -I$(REPO_PATH) $(addprefix -I$(REPO_PATH)/, $(inc_dependencies))

lib_dependencies = libspike_main.a libriscv.a libdisasm.a libsoftfloat.a libfesvr.a libfdt.a
INC_LIBS  = $(addprefix $(REPO_BUILD_PATH)/, $(lib_dependencies))

NAME = riscv32-spike-so
BUILD_DIR = $(NEW_CORE_HOME)/build
BINARY = $(BUILD_DIR)/$(NAME)
SRCS = difftest.cc

$(shell mkdir -p $(BUILD_DIR))

$(BINARY): $(SRCS)
	g++ -std=c++17 -O2 -shared -fPIC -fvisibility=hidden $(INC_PATH) $(SRCS) $(INC_LIBS) -o $@

clean:
	rm -rf $(BUILD_DIR)/$(NAME)

all: $(BINARY)
.PHONY: all clean
.DEFAULT_GOAL = all