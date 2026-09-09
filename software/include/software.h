#ifndef __SOFTWARE_H__
#define __SOFTWARE_H__

#include <stdbool.h>

void halt(int code);

#define LENGTH(x) (sizeof(x) / sizeof((x)[0]))

#define uint32_t unsigned int
#define uint16_t unsigned short
#define uint8_t unsigned char

__attribute__((noinline))
void check(bool cond) {
  if (!cond) halt(1);
}

static inline void outb(uint32_t addr, uint8_t  data) { *(volatile uint8_t  *)addr = data; }

void putch(char ch) { outb(0xa0000000, ch); }

#define putstr(s) \
  ({ for (const char *p = s; *p; p++) putch(*p); })

#endif
