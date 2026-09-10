#ifndef __FPU_H__
#define __FPU_H__

float fabsf(float x) { return x < 0 ? -x : x; }

int cmp_matrix(float *C, float *D, int n, int m, float eps) {
    for (int i = 0; i < n * m; i++) {
        float d   = fabsf(C[i] - D[i]);
        float d_  = fabsf(D[i]);
        float tol = d_ < 1.0f ? eps : eps * d_;
        if (d > tol) return 0;
    }
    return 1;
}

void put_float_decimal(float f) {
    union { float f; unsigned u; } bits;
    bits.f = f;
    if ((bits.u & 0x7f800000) == 0x7f800000) { putstr("inf/nan"); return; }
    if (f < 0.0f) { putch('-'); f = -f; }
    unsigned ip = (unsigned)f;
    char tmp[12];
    int n = 0;
    do { tmp[n++] = '0' + ip % 10; ip /= 10; } while (ip);
    while (n) putch(tmp[--n]);
    putch('.');
    f -= (float)(unsigned)f;
    for (int i = 0; i < 6; i++) {
        f *= 10.0f;
        unsigned dg = (unsigned)f;
        putch('0' + dg);
        f -= (float)dg;
    }
}

float fmadd(float a, float b, float c) {
    float res;
    asm volatile("fmadd.s %0, %1, %2, %3" : "=f"(res) : "f"(a), "f"(b), "f"(c));
    return res;
}

#endif