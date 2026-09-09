#include "software.h"
#include "fpu.h"   

static float my_expf(float x) {
    float sum = 1.0f;
    float term = 1.0f;
    for (int i = 1; i < 20; i++) {
        term *= x / i;
        sum += term;
        if (term < 1e-7f && term > -1e-7f) break;
    }
    return sum;
}

static float sigmoid(float x) {
    if (x >= 0) {
        float e = my_expf(-x);
        return 1.0f / (1.0f + e);
    } else {
        float e = my_expf(x);
        return e / (1.0f + e);
    }
}

static void softmax(const float *input, float *output, int n) {
    float max_val = input[0];
    for (int i = 1; i < n; i++) {
        if (input[i] > max_val) max_val = input[i];
    }
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        output[i] = my_expf(input[i] - max_val);
        sum += output[i];
    }
    for (int i = 0; i < n; i++) {
        output[i] /= sum;
    }
}

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

static void sgd_update(float *W, const float *dW, float *b, const float *db, int rows, int cols, float lr) {
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            W[i * cols + j] -= lr * dW[i * cols + j];
        }
        b[i] -= lr * db[i];
    }
}

int main() {
    putstr("=== Neural Network Training with Softmax (2-16-8-2) ===\n");

    static const float X[2][2] = {
        {0.1f, 0.2f},   // 类别0
        {0.8f, 0.9f}    // 类别1
    };
    static const float Y_true[2][2] = {
        {1.0f, 0.0f},   // one-hot for class 0
        {0.0f, 1.0f}    // one-hot for class 1
    };

    static float W1[16][2] = {
        { +0.0837f, -0.2850f },
        { -0.1350f, -0.1661f },
        { +0.1419f, +0.1060f },
        { +0.2353f, -0.2478f },
        { -0.0468f, -0.2821f },
        { -0.1688f, +0.0032f },
        { -0.2841f, -0.1807f },
        { +0.0899f, +0.0270f },
        { -0.1677f, +0.0536f },
        { +0.1857f, -0.2961f },
        { +0.1835f, +0.1189f },
        { -0.0958f, -0.2067f },
        { +0.2743f, -0.0980f },
        { -0.2444f, -0.2420f },
        { +0.2085f, +0.0622f },
        { +0.1843f, +0.1378f }
    };
    static float b1[16] = { +0.0145f, +0.1892f, -0.0486f, +0.0208f, +0.1318f, +0.0474f, +0.1447f, +0.0309f, +0.0818f, -0.1817f, -0.1088f, -0.0842f, -0.1681f, -0.1069f, -0.1596f, -0.0888f };

    static float W2[8][16] = {
        { +0.0814f, -0.0811f, -0.0779f, -0.1743f, -0.1398f, +0.2620f, +0.0888f, +0.0655f, -0.1973f, +0.1375f, -0.2020f, -0.0723f, +0.2937f, +0.0840f, +0.0342f, +0.1108f },
        { +0.2057f, +0.1656f, -0.1626f, -0.2807f, -0.1107f, -0.1394f, -0.1734f, +0.2657f, +0.2258f, -0.1112f, +0.0933f, -0.0626f, +0.2487f, -0.0247f, -0.1411f, -0.1520f },
        { +0.0368f, -0.1424f, +0.0508f, +0.2387f, -0.0604f, -0.1684f, +0.2985f, +0.0057f, -0.2455f, -0.2717f, -0.2342f, +0.0765f, +0.1752f, -0.0467f, -0.2619f, -0.0710f },
        { +0.2977f, +0.0175f, +0.2826f, +0.2165f, -0.2931f, +0.1324f, +0.1090f, +0.0222f, -0.1399f, +0.0846f, -0.2331f, -0.0391f, -0.0278f, +0.2723f, +0.2255f, -0.1420f },
        { +0.0004f, -0.1928f, +0.2476f, +0.2223f, -0.1209f, +0.0834f, +0.0654f, -0.2083f, +0.1575f, +0.0236f, +0.1672f, +0.0182f, -0.2997f, -0.1055f, -0.2883f, +0.2575f },
        { +0.2272f, +0.1990f, -0.1155f, -0.2652f, +0.2268f, +0.2682f, -0.2486f, -0.0084f, -0.2585f, +0.1564f, +0.1595f, -0.2230f, -0.0148f, +0.0299f, -0.1410f, +0.2235f },
        { -0.0461f, -0.1729f, +0.0236f, +0.1380f, -0.1793f, -0.1130f, +0.2971f, +0.0899f, -0.0371f, +0.0105f, -0.2274f, -0.1652f, -0.0971f, +0.0530f, -0.1619f, -0.1679f },
        { -0.2574f, +0.0787f, -0.1626f, +0.2433f, +0.2158f, -0.2575f, -0.1572f, +0.1014f, -0.1715f, -0.2206f, +0.2613f, +0.0426f, -0.0164f, +0.1708f, +0.1845f, -0.1858f }
    };
    static float b2[8] = { -0.1612f, -0.0276f, -0.0306f, -0.0132f, +0.0916f, +0.0693f, +0.1937f, -0.1606f };

    static float W3[2][8] = {
        { -0.0584f, -0.0964f, +0.2170f, -0.1508f, -0.1859f, -0.0308f, -0.0469f, -0.1329f },
        { -0.1501f, +0.2540f, -0.0341f, +0.2168f, +0.0302f, -0.2696f, +0.2996f, +0.2016f }
    };
    static float b3[2] = { +0.1876f, +0.1705f };

    const float lr = 1.0f;
    const int epochs = 100;
    const int num_samples = 2;

    static float h1[16], z1[16];       
    static float h2[8], z2[8];       
    static float z3[2], y_pred[2];   

    static float dW1[16][2];      
    static float db1[16];
    static float dW2[8][16];
    static float db2[8];
    static float dW3[2][8];
    static float db3[2];

    for (int epoch = 0; epoch < epochs; epoch++) {
        for (int i = 0; i < 16; i++) {
            for (int j = 0; j < 2; j++) dW1[i][j] = 0.0f;
            db1[i] = 0.0f;
        }
        for (int i = 0; i < 8; i++) {
            for (int j = 0; j < 16; j++) dW2[i][j] = 0.0f;
            db2[i] = 0.0f;
        }
        for (int i = 0; i < 2; i++) {
            for (int j = 0; j < 8; j++) dW3[i][j] = 0.0f;
            db3[i] = 0.0f;
        }

        for (int s = 0; s < num_samples; s++) {
            // 前向传播
            // 隐藏层1
            matvec_mul((const float*)W1, X[s], z1, 16, 2);
            vec_add(z1, b1, 16);
            for (int i = 0; i < 16; i++) h1[i] = sigmoid(z1[i]);

            // 隐藏层2
            matvec_mul((const float*)W2, h1, z2, 8, 16);
            vec_add(z2, b2, 8);
            for (int i = 0; i < 8; i++) h2[i] = sigmoid(z2[i]);

            // 输出层
            matvec_mul((const float*)W3, h2, z3, 2, 8);
            vec_add(z3, b3, 2);
            softmax(z3, y_pred, 2);

            // 反向传播（梯度计算）
            float delta3[2];
            for (int i = 0; i < 2; i++) {
                delta3[i] = y_pred[i] - Y_true[s][i];
            }

            for (int i = 0; i < 2; i++) {
                db3[i] += delta3[i];
                for (int j = 0; j < 8; j++) {
                    dW3[i][j] += delta3[i] * h2[j];
                }
            }

            float delta2[8];
            for (int i = 0; i < 8; i++) {
                float sum = 0.0f;
                for (int j = 0; j < 2; j++) {
                    sum += W3[j][i] * delta3[j];
                }
                delta2[i] = sum * h2[i] * (1.0f - h2[i]);
            }

            for (int i = 0; i < 8; i++) {
                db2[i] += delta2[i];
                for (int j = 0; j < 16; j++) {
                    dW2[i][j] += delta2[i] * h1[j];
                }
            }

            float delta1[16];
            for (int i = 0; i < 16; i++) {
                float sum = 0.0f;
                for (int j = 0; j < 8; j++) {
                    sum += W2[j][i] * delta2[j];
                }
                delta1[i] = sum * h1[i] * (1.0f - h1[i]);
            }

            for (int i = 0; i < 16; i++) {
                db1[i] += delta1[i];
                for (int j = 0; j < 2; j++) {
                    dW1[i][j] += delta1[i] * X[s][j];
                }
            }
        }

        for (int i = 0; i < 16; i++) {
            db1[i] /= 2.0f;
            for (int j = 0; j < 2; j++) dW1[i][j] /= 2.0f;
        }
        for (int i = 0; i < 8; i++) {
            db2[i] /= 2.0f;
            for (int j = 0; j < 16; j++) dW2[i][j] /= 2.0f;
        }
        for (int i = 0; i < 2; i++) {
            db3[i] /= 2.0f;
            for (int j = 0; j < 8; j++) dW3[i][j] /= 2.0f;
        }

        // 更新权重
        sgd_update((float*)W1, (const float*)dW1, b1, db1, 16, 2, lr);
        sgd_update((float*)W2, (const float*)dW2, b2, db2, 8, 16, lr);
        sgd_update((float*)W3, (const float*)dW3, b3, db3, 2, 8, lr);
    }

    // 训练结束，对两个样本再次前向传播获取预测
    float preds[2][2];

    for (int s = 0; s < 2; s++) {
        matvec_mul((const float*)W1, X[s], z1, 16, 2);
        vec_add(z1, b1, 16);
        for (int i = 0; i < 16; i++) h1[i] = sigmoid(z1[i]);

        matvec_mul((const float*)W2, h1, z2, 8, 16);
        vec_add(z2, b2, 8);
        for (int i = 0; i < 8; i++) h2[i] = sigmoid(z2[i]);

        matvec_mul((const float*)W3, h2, z3, 2, 8);
        vec_add(z3, b3, 2);
        softmax(z3, preds[s], 2);
    }

    // ---------- 预期预测（用与设备端完全一致的 float 前向+训练算法计算得到） ----------
    static const float expected_preds[2][2] = {
        {0.885639489f, 0.114360504f},   // 样本1 应接近类别0
        {0.112244226f, 0.887755811f}    // 样本2 应接近类别1
    };

    // 相对误差容忍 1e-4
    if (cmp_matrix((float*)preds, (float*)expected_preds, 2, 2, 1e-4f)) {
        putstr("Test PASSED! Neural network training with softmax works correctly.\n");
    } else {
        putstr("Test FAILED! Training or FPU computations are incorrect.\n");
        halt(1);
    }

    return 0;
}
