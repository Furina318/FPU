OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
  . = 0x80000000;

  .text : {
    *(entry)          
    *(.text.init)     
    *(.text*)
  }

  .rodata : {
    *(.rodata*)
  }

  .data : {
    *(.data*)
    *(.sdata*)
  }

  .bss : {
    *(.bss*)
    *(.sbss*)
    *(.scommon)
  }

  /* 栈空间:向上 32KB */
  . = ALIGN(0x1000);
  . += 0x8000;
  _stack_pointer = .;

  end = .;
  _end = .;
}
