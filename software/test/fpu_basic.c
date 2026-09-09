// FPU 集成最小验证(纯寄存器/内存细粒度步骤)
// 失败步骤号从 a0(halt code)获取
#include <stdint.h>
#include "../include/software.h"

volatile uint32_t mem32 __attribute__((aligned(4)));

#define T(cond, code) do { if (!(cond)) halt(code); } while (0)

int main() {
    uint32_t r;

    // 1. fmv.w.x -> fmv.x.w 纯寄存器往返(背靠背依赖)
    asm volatile("fmv.w.x fa5, %1\n\t"
                 "fmv.x.w %0, fa5"
                 : "=r"(r) : "r"(0x3f800000));
    T(r == 0x3f800000, 1);

    // 2. FLW 加载 + 回读
    mem32 = 0x40200000; // 2.5
    asm volatile("flw fa5, %1\n\t"
                 "fmv.x.w %0, fa5"
                 : "=r"(r) : "m"(mem32));
    T(r == 0x40200000, 2);

    // 3. fmv.w.x -> FSW 存储, 整数回读
    mem32 = 0;
    asm volatile("fmv.w.x fa5, %1\n\t"
                 "fsw fa5, %0"
                 : "=m"(mem32) : "r"(0x3fa00000)); // 1.25
    T(mem32 == 0x3fa00000, 3);

    // 4. FADD: 1.0 + 2.0 = 3.0 (fma 类, 需停顿等待)
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fadd.s fa2, fa0, fa1\n\t"
                 "fmv.x.w %0, fa2"
                 : "=r"(r) : "r"(0x3f800000), "r"(0x40000000));
    T(r == 0x40400000, 4);

    // 5. fcsr 写读
    asm volatile("csrw fcsr, %1\n\t"
                 "csrr %0, fcsr"
                 : "=r"(r) : "r"(0x40));
    T(r == 0x40, 5);

    // 6. FMUL: 2*3=6
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fmul.s fa2, fa0, fa1\n\t"
                 "fmv.x.w %0, fa2"
                 : "=r"(r) : "r"(0x40000000), "r"(0x40400000));
    T(r == 0x40c00000, 6);

    // 7. 依赖背靠背: (1+2)*3=9 (fadd 写回后立即被 fmul 读取)
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fadd.s fa2, fa0, fa1\n\t"
                 "fmv.w.x fa1, %3\n\t"
                 "fmul.s fa3, fa2, fa1\n\t"
                 "fmv.x.w %0, fa3"
                 : "=r"(r) : "r"(0x3f800000), "r"(0x40000000), "r"(0x40400000));
    T(r == 0x41100000, 7);

    // 8. FMIN/FMAX: min(1,-2)=-2, max(1,-2)=1
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fmin.s fa2, fa0, fa1\n\t"
                 "fmax.s fa3, fa0, fa1\n\t"
                 "fmv.x.w %0, fa2"
                 : "=r"(r) : "r"(0x3f800000), "r"(0xc0000000));
    T(r == 0xc0000000, 8);
    asm volatile("fmv.x.w %0, fa3" : "=r"(r));
    T(r == 0x3f800000, 9);

    // 10. FEQ/FLT/FLE: 1==1, 1<2, 2<=2
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "feq.s %0, fa0, fa1"
                 : "=r"(r) : "r"(0x3f800000), "r"(0x3f800000));
    T(r == 1, 10);
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "flt.s %0, fa0, fa1"
                 : "=r"(r) : "r"(0x3f800000), "r"(0x40000000));
    T(r == 1, 11);
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fle.s %0, fa0, fa1"
                 : "=r"(r) : "r"(0x40000000), "r"(0x40000000));
    T(r == 1, 12);

    // 13. FSGNJN/FSGNJX: -2 变 +2 (符号取反/异或)
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fmv.w.x fa1, %2\n\t"
                 "fsgnjn.s fa2, fa0, fa1\n\t"
                 "fsgnjx.s fa3, fa0, fa1\n\t"
                 "fmv.x.w %0, fa2"
                 : "=r"(r) : "r"(0xc0000000), "r"(0xc0000000));
    T(r == 0x40000000, 13);
    asm volatile("fmv.x.w %0, fa3" : "=r"(r));
    T(r == 0x40000000, 14);

    // 15. FCVT.W.S: 3.7 -> 4 (先恢复 RNE, 前文步骤 5 将 frm 置为 RDN)
    asm volatile("csrw fcsr, %1\n\t"
                 "fmv.w.x fa0, %2\n\t"
                 "fcvt.w.s %0, fa0"
                 : "=r"(r) : "r"(0), "r"(0x406ccccd)); // 3.7
    T(r == 4, 15);

    // 16. FCVT.S.W: 5 -> 5.0
    asm volatile("li a5, 5\n\t"
                 "fcvt.s.w fa0, a5\n\t"
                 "fmv.x.w %0, fa0"
                 : "=r"(r) : : "a5");
    T(r == 0x40a00000, 16);

    // 17. FCLASS: 1.0(+normal) -> bit6(0x40); -Inf -> bit0
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fclass.s %0, fa0"
                 : "=r"(r) : "r"(0x3f800000));
    T(r == 0x40, 17);
    asm volatile("fmv.w.x fa0, %1\n\t"
                 "fclass.s %0, fa0"
                 : "=r"(r) : "r"(0xff800000));
    T(r == 0x01, 18);

    // 19. 动态舍入: frm=RUP 时 3.0+0.5 仍精确; frm 读回
    asm volatile("csrw fcsr, %1\n\t"
                 "fmv.w.x fa0, %2\n\t"
                 "fmv.w.x fa1, %3\n\t"
                 "fadd.s fa2, fa0, fa1\n\t"
                 "fmv.x.w %0, fa2"
                 : "=r"(r) : "r"(0x60), "r"(0x40400000), "r"(0x3f000000)); // 3.0 + 0.5
    T(r == 0x40600000, 19);

    // 20. FMADD(四寄存器, rs3 路径): 2*3+4=10; FMSUB: 2*3-4=2
    asm volatile("csrw fcsr, %1\n\t"
                 "fmv.w.x fa0, %2\n\t"
                 "fmv.w.x fa1, %3\n\t"
                 "fmv.w.x fa2, %4\n\t"
                 "fmadd.s fa3, fa0, fa1, fa2\n\t"
                 "fmsub.s fa4, fa0, fa1, fa2\n\t"
                 "fmv.x.w %0, fa3"
                 : "=r"(r) : "r"(0), "r"(0x40000000), "r"(0x40400000), "r"(0x40800000));
    T(r == 0x41200000, 20); // 10.0
    asm volatile("fmv.x.w %0, fa4" : "=r"(r));
    T(r == 0x40000000, 21); // 2.0

    return 0;
}
