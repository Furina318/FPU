#include "software.h"
#include "fpu.h"

int main() {
    putstr("Matrix FPU Test\n");

    float A[4] = {1.2f, 2.4f, 3.6f, 4.8f};
    float B[4] = {4.3f, 3.2f, 2.8f, 1.4f};
    float C[4] = {0};
    float D[4] = {11.88f, 7.20f, 28.92f, 18.24f};

    // 矩阵乘法：C = A * B
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++)
            for (int k = 0; k < 2; k++)
                C[i*2+j] += A[i*2+k] * B[k*2+j];

    // 误差容忍 1e-6
    if (cmp_matrix(C, D, 2, 2, 1e-6f)) {
        putstr("FPU matrix multiplication PASSED!\n");
    } else {
        putstr("FPU matrix multiplication FAILED!\n");
        halt(1);
    }

    return 0;
}