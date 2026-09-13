#include <stdint.h>
static const uint32_t A[] = { 0x5d7f7f08u, 0x1f156458u, 0x055dbe0eu };
static const uint32_t B[] = { 0x05804fe5u, 0x9f180000u, 0x8a0d4eafu };
static const uint32_t C[] = { 0x6f9d0000u, 0x7fb223d1u, 0x68249e64u };
static const uint32_t E[] = { 0xef9d0000u, 0x7fc00000u, 0xe8249e64u };
static const uint32_t F[] = { 0x00000001u, 0x00000010u, 0x00000001u };
int main() {
    union { float f; uint32_t u; } u;
    register uint32_t i, r, fl;
    for (i = 0; i < 3; i++) {
        __asm__ volatile("csrw fcsr, x0");
        u.u = A[i]; float aa = u.f;
        u.u = B[i]; float bb = u.f;
        u.u = C[i]; float cc = u.f;
        float rr = __builtin_fmaf(aa, bb, cc);
        u.f = rr; r = u.u;
        if (r != E[i]) { return ((int)(i + 1) << 16) | (int)((r >> 16) & 0xffff); }
        __asm__ volatile("csrr %0, fcsr" : "=r"(fl));
        fl &= 0x1fu;
        if (fl != F[i]) { return -(int)(i + 1); }
    }
    return 0;
}
