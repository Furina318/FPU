# FPU 测试环境

架构：`RV32F 单精度浮点`

本目录包含：

- `rtl`：存放FPU单精度浮点运算单元RTL代码
- `tb`：对FPU模块做单元级验证测试
- `software`：编写存放包含浮点测试的软件，包含riscv-arch-test中有关单精度浮点相关的测试移植内容
- `cpu`: 存储接入FPU的RV32IMCF顺序单发射流水线

```
.
├── cpu
│   ├── include
│   ├── Kconfig
│   ├── Makefile
│   ├── pipeline-FPU
│   ├── tools
│   └── wave.vcd
├── Makefile
├── README.md
├── rtl
├── software
│   ├── asm-test
│   ├── include
│   ├── Makefile
│   ├── RV32IMF.mk
│   ├── scripts
│   ├── start.S
│   ├── test
│   └── trm.c
└── tb
```
