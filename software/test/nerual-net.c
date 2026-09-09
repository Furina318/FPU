#include "software.h"
#include "fpu.h"   

// ---------- 自定义 exp 近似（泰勒级数，适用于负输入） ----------
static float my_expf(float x) {
    // 只处理 x <= 0，保证级数单调收敛
    float sum = 1.0f;
    float term = 1.0f;
    for (int i = 1; i < 20; i++) {
        term *= x / i;
        sum += term;
        // 当项足够小时提前退出
        if (term < 1e-7f && term > -1e-7f) break;
    }
    return sum;
}

// ---------- Sigmoid 激活函数 ----------
static float sigmoid(float x) {
    if (x >= 0) {
        float e = my_expf(-x);
        return 1.0f / (1.0f + e);
    } else {
        float e = my_expf(x);
        return e / (1.0f + e);
    }
}

// ---------- 辅助函数 ----------
static void matvec_mul(const float *M, const float *x, float *y, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        y[i] = 0.0f;
        for (int j = 0; j < cols; j++) {
            y[i] += M[i * cols + j] * x[j];
        }
    }
}

static void vec_add(float *y, const float *bias, int n) {
    for (int i = 0; i < n; i++) y[i] += bias[i];
}

static void vec_sigmoid(float *y, int n) {
    for (int i = 0; i < n; i++) y[i] = sigmoid(y[i]);
}

int main() {
    putstr("=== Neural Network with Sigmoid (8-16-8-4) ===\n");

    // ---------- 输入 (8维) ----------
    static const float x[8] = {
        0.12f, -0.34f, 0.56f, -0.78f,
        0.91f, -0.23f, 0.45f, -0.67f
    };

    // ---------- 第一层：16个神经元，输入8 ----------
    static const float W1[16][8] = {
        { 0.2f, 0.4f, -0.1f, 0.3f, 0.1f, -0.2f, 0.5f, 0.3f },
        { 0.1f, 0.5f, 0.2f, -0.2f, 0.3f, 0.4f, -0.1f, 0.2f },
        { 0.3f, -0.2f, 0.4f, 0.1f, -0.3f, 0.2f, 0.1f, -0.4f },
        { -0.1f, 0.2f, 0.3f, 0.5f, 0.2f, -0.1f, 0.4f, 0.3f },
        { 0.4f, 0.1f, -0.3f, 0.2f, 0.5f, 0.3f, -0.2f, 0.1f },
        { 0.2f, -0.4f, 0.5f, 0.1f, -0.1f, 0.3f, 0.2f, -0.3f },
        { -0.3f, 0.3f, 0.2f, 0.4f, -0.2f, 0.1f, 0.3f, 0.5f },
        { 0.5f, 0.2f, -0.2f, 0.3f, 0.4f, -0.1f, 0.2f, -0.4f },
        { 0.1f, -0.3f, 0.4f, 0.2f, 0.3f, 0.5f, -0.1f, 0.2f },
        { 0.2f, 0.3f, -0.1f, 0.4f, -0.2f, 0.1f, 0.3f, 0.5f },
        { -0.2f, 0.5f, 0.1f, -0.3f, 0.4f, 0.2f, -0.1f, 0.3f },
        { 0.3f, -0.1f, 0.5f, 0.2f, 0.1f, -0.4f, 0.3f, 0.2f },
        { 0.4f, 0.2f, -0.3f, 0.5f, 0.1f, 0.3f, -0.2f, 0.4f },
        { -0.1f, 0.4f, 0.2f, -0.2f, 0.3f, 0.5f, 0.1f, -0.3f },
        { 0.5f, -0.2f, 0.3f, 0.1f, -0.4f, 0.2f, 0.4f, 0.3f },
        { 0.2f, 0.1f, 0.4f, -0.3f, 0.5f, -0.1f, 0.2f, 0.3f }
    };
    static const float b1[16] = {
        0.1f, -0.2f, 0.3f, -0.1f, 0.2f, 0.0f, -0.3f, 0.4f,
        0.5f, -0.4f, 0.2f, -0.3f, 0.1f, 0.6f, -0.2f, 0.3f
    };

    // ---------- 第二层：8个神经元，输入16 ----------
    static const float W2[8][16] = {
        { 0.3f, -0.1f, 0.4f, 0.2f, 0.1f, 0.3f, -0.2f, 0.4f,
          0.2f, -0.3f, 0.1f, 0.5f, -0.1f, 0.3f, 0.2f, -0.4f },
        { 0.2f, 0.5f, -0.1f, 0.3f, 0.4f, -0.2f, 0.1f, 0.2f,
         -0.3f, 0.4f, 0.2f, -0.1f, 0.5f, 0.1f, -0.2f, 0.3f },
        { -0.1f, 0.2f, 0.3f, -0.4f, 0.5f, 0.1f, 0.2f, -0.1f,
          0.3f, -0.2f, 0.4f, 0.1f, -0.3f, 0.5f, 0.2f, 0.1f },
        { 0.4f, 0.1f, 0.2f, 0.5f, -0.3f, 0.2f, 0.3f, 0.1f,
          0.2f, 0.5f, -0.1f, 0.3f, 0.4f, -0.2f, 0.1f, 0.3f },
        { 0.2f, -0.3f, 0.4f, 0.1f, 0.3f, -0.1f, 0.5f, 0.2f,
         -0.2f, 0.1f, 0.3f, 0.4f, -0.1f, 0.2f, 0.5f, -0.3f },
        { -0.2f, 0.4f, 0.1f, 0.3f, 0.2f, 0.4f, -0.1f, 0.3f,
          0.5f, -0.1f, 0.2f, -0.3f, 0.4f, 0.1f, 0.3f, 0.2f },
        { 0.1f, -0.2f, 0.5f, 0.3f, -0.4f, 0.2f, 0.1f, 0.4f,
          0.3f, 0.2f, -0.1f, 0.5f, -0.2f, 0.4f, 0.1f, -0.3f },
        { 0.3f, 0.4f, -0.2f, 0.1f, 0.2f, -0.3f, 0.5f, -0.1f,
          0.4f, 0.1f, 0.3f, -0.2f, 0.2f, 0.5f, -0.1f, 0.3f }
    };
    static const float b2[8] = {
        0.2f, -0.1f, 0.3f, -0.2f, 0.1f, 0.4f, -0.3f, 0.2f
    };

    // ---------- 第三层：4个神经元，输入8 ----------
    static const float W3[4][8] = {
        { 0.5f, 0.1f, -0.2f, 0.3f, 0.4f, 0.2f, -0.1f, 0.3f },
        { 0.1f, 0.4f, 0.3f, -0.1f, 0.2f, 0.5f, -0.2f, 0.3f },
        { 0.3f, -0.2f, 0.1f, 0.4f, -0.3f, 0.2f, 0.5f, -0.1f },
        { 0.2f, 0.3f, -0.1f, 0.5f, 0.1f, -0.2f, 0.3f, 0.4f }
    };
    static const float b3[4] = { 0.1f, -0.2f, 0.3f, -0.1f };

    // ---------- 缓冲区 ----------
    float h1[16], h2[8], y[4];

    // 第一层
    matvec_mul((const float*)W1, x, h1, 16, 8);
    vec_add(h1, b1, 16);
    vec_sigmoid(h1, 16);

    // 第二层
    matvec_mul((const float*)W2, h1, h2, 8, 16);
    vec_add(h2, b2, 8);
    vec_sigmoid(h2, 8);

    // 第三层（输出）
    matvec_mul((const float*)W3, h2, y, 4, 8);
    vec_add(y, b3, 4);
    vec_sigmoid(y, 4);

    static const float expected[4] = {
        0.782593012f, // y0
        0.736579716f, // y1
        0.730951369f, // y2
        0.729744852f  // y3
    };

    if (cmp_matrix(y, (float*)expected, 1, 4, 1e-4f)) {
        putstr("Test PASSED! Sigmoid network forward propagation works.\n");
    } else {
        putstr("Test FAILED! Check FPU or sigmoid implementation.\n");
        halt(1);
    }

    return 0;
}