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

float fmadd(float a, float b, float c) {
    float res;
    asm volatile("fmadd.s %0, %1, %2, %3" : "=f"(res) : "f"(a), "f"(b), "f"(c));
    return res;
}

#endif