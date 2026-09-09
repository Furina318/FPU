`include "fpu_config.vh"

//////////////////////////////////////////////////////////////////////////////
//
// fma_unit - 融合乘加单元
//
// 支持：
//   FADD / FSUB / FMUL / FMADD / FMSUB / FNMADD / FNMSUB
//   全部统一成 a*b + c 计算：FADD/FSUB 置 a=1.0、c=±src2；
//   FMUL 置 c=0；FMSUB/FNMSUB 对 c 取反；FNMADD/FNMSUB 对 a 取反。
//
// 结构（2 级流水）：
//   stage0：操作数选择 + Booth 编码/Wallace 树求乘积，
//           结果以进位保存形式 (s, cout2) 连同元数据锁存
//   stage1：乘积与 c 按大 LSB 对齐相加、规范化/次正规化、舍入、打包
//
// 输入：
//   操作数不直接收 IEEE-754 位型，而是 fpu 顶层 fpu_decoder 解包后的
//   sign/exp/sig/分类标志（次正规数已规范化，exp 为真实二进制指数），
//   避免各模块重复前导零检测等拆包逻辑。
//
// 数值约定：
//   sig 为 24 位显式前导 1 的有效数，小数点位于 bit23；
//   exp 为 9 位有符号无偏指数，范围约 -149 ~ +127。
//////////////////////////////////////////////////////////////////////////////

module fma_unit #(
    parameter ID_WIDTH = 5
)(
    input  wire                clk        ,
    input  wire                rst        ,

    input  wire                issue_valid,
    input  wire [ID_WIDTH-1:0] issue_id   ,
    input  wire [         6:0] op         ,
    input  wire [         2:0] rm         ,

    // 操作数拆包
    input  wire               s1_sign, s2_sign, s3_sign,
    input  wire signed [ 8:0] s1_exp , s2_exp , s3_exp ,
    input  wire        [23:0] s1_sig , s2_sig , s3_sig ,
    input  wire               s1_zero, s2_zero, s3_zero,
    input  wire               s1_inf , s2_inf , s3_inf ,
    input  wire               s1_nan , s2_nan , s3_nan ,
    input  wire               s1_snan, s2_snan, s3_snan,

    input  wire                flush      ,
    input  wire [ID_WIDTH-1:0] flush_id   ,

    output wire                wb_valid   ,
    output wire [ID_WIDTH-1:0] wb_id      ,
    output wire [        31:0] wb_result  ,
    output wire [         4:0] wb_fflags
);

    wire is_fadd   = (op == `FADD_S);
    wire is_fsub   = (op == `FSUB_S);
    wire is_fmul   = (op == `FMUL_S);
    wire is_fmadd  = (op == `FMADD_S);
    wire is_fmsub  = (op == `FMSUB_S);
    wire is_fnmadd = (op == `FNMADD_S);
    wire is_fnmsub = (op == `FNMSUB_S);
    wire is_faddsub = is_fadd | is_fsub;

    // 统一成 a*b + c
    //   FADD/FSUB     : a = 1.0, b = src1, c = ±src2
    //   FMUL          : a = src1, b = src2, c = ±0（符号 src1^src2）
    //   FMADD/FMSUB   : a = src1, b = src2, c = ±src3
    //   FNMADD/FNMSUB : a 取反（乘积取反），c 同 FMSUB 规则
    // 取反只影响 sign 位：exp/sig 与分类标志均不变，±0 分类仍为 zero。
    wire is_neg_op = is_fnmadd | is_fnmsub;

    wire        a_sign = is_faddsub ? 1'b0       :
                         is_neg_op  ? ~s1_sign   :
                                      s1_sign    ;
                                      
    wire signed [ 8:0] a_exp  = is_faddsub ? 9'sd0      : s1_exp;
    wire        [23:0] a_sig  = is_faddsub ? 24'h800000 : s1_sig;
    wire               a_zero = is_faddsub ? 1'b0       : s1_zero;
    wire               a_inf  = is_faddsub ? 1'b0       : s1_inf;
    wire               a_nan  = is_faddsub ? 1'b0       : s1_nan;
    wire               a_snan = is_faddsub ? 1'b0       : s1_snan;

    wire               b_sign = is_faddsub ? s1_sign : s2_sign;
    wire signed [ 8:0] b_exp  = is_faddsub ? s1_exp  : s2_exp;
    wire        [23:0] b_sig  = is_faddsub ? s1_sig  : s2_sig;
    wire               b_zero = is_faddsub ? s1_zero : s2_zero;
    wire               b_inf  = is_faddsub ? s1_inf  : s2_inf;
    wire               b_nan  = is_faddsub ? s1_nan  : s2_nan;
    wire               b_snan = is_faddsub ? s1_snan : s2_snan;

    wire c_from_s3 = is_fmadd | is_fmsub | is_fnmadd | is_fnmsub;
    // FNMADD = -(a*b) + c (c 不取反)；FNMSUB = -(a*b) - c (c 取反)
    wire c_neg     = is_fsub  | is_fmsub | is_fnmsub;
    wire        c_sign = is_faddsub ? (is_fsub ? ~s2_sign : s2_sign) :
                         is_fmul    ? (s1_sign ^ s2_sign)            :
                         c_neg      ? ~s3_sign                       :
                                      s3_sign                        ;

    wire signed [ 8:0] c_exp  = is_fmul ? 9'sd0 : (c_from_s3 ? s3_exp : s2_exp);
    wire        [23:0] c_sig  = is_fmul ? 24'd0 : (c_from_s3 ? s3_sig : s2_sig);
    wire               c_zero = is_fmul ? 1'b1 : (c_from_s3 ? s3_zero : s2_zero);
    wire               c_inf  = is_fmul ? 1'b0 : (c_from_s3 ? s3_inf  : s2_inf);
    wire               c_nan  = is_fmul ? 1'b0 : (c_from_s3 ? s3_nan  : s2_nan);
    wire               c_snan = is_fmul ? 1'b0 : (c_from_s3 ? s3_snan : s2_snan);

    // 特殊值判定：先得乘积元数据（prod_*），再与 c 组合判定特殊路径结果
    wire mul_invalid   = (a_zero & b_inf) | (a_inf & b_zero);  // 0*Inf -> NaN
    wire prod_nan      = a_nan | b_nan | mul_invalid;
    wire prod_inf      = (a_inf | b_inf) & ~prod_nan;
    wire prod_inf_sign = a_sign ^ b_sign;
    wire prod_zero     = (a_zero | b_zero) & ~prod_nan;

    // 乘积 Inf 与 c 符号相反的 Inf 相加：结果为 NaN 并置 NV
    wire any_nan      = a_nan | b_nan | c_nan | prod_nan;
    wire inf_opposite = prod_inf & c_inf & (prod_inf_sign != c_sign);
    wire invalid      = (a_snan | b_snan | c_snan) | mul_invalid | inf_opposite;
    wire sp_nan       = any_nan | inf_opposite;

    // 特殊路径直接产出的三类结果：NaN / 乘积无穷 / c 无穷
    wire sp_inf_result = ~sp_nan & prod_inf;
    wire sp_c_inf_result = ~sp_nan & c_inf & ~prod_inf;
    wire is_special = sp_nan | sp_inf_result | sp_c_inf_result;

    reg [31:0] sp_result;
    reg [4:0]  sp_fflags;
    always @(*) begin
        sp_result = 32'h7fc00000;
        sp_fflags = 5'd0;
        if (sp_nan) begin
            sp_result = 32'h7fc00000;
            sp_fflags[`NV] = invalid;
        end else if (sp_inf_result) begin
            sp_result = {prod_inf_sign, 8'hFF, 23'd0};
            sp_fflags = 5'd0;
        end else if (sp_c_inf_result) begin
            sp_result = {c_sign, 8'hFF, 23'd0};
            sp_fflags = 5'd0;
        end
    end

    // 有限数运算所需的乘积元数据
    wire signed [10:0] a_exp11 = $signed({{2{a_exp[8]}}, a_exp});
    wire signed [10:0] b_exp11 = $signed({{2{b_exp[8]}}, b_exp});
    wire signed [10:0] c_exp11 = $signed({{2{c_exp[8]}}, c_exp});

    // 乘积（24+24=48 位）的 LSB 指数 = a_exp + b_exp - 46；
    // c 的 LSB 指数 = c_exp - 23。两者在 stage1 按 LSB 指数对齐相加
    wire signed [10:0] p_exp = a_exp11 + b_exp11 - 11'sd46;
    wire signed [10:0] c_lsb = c_exp11 - 11'sd23;

    wire p_sign = a_sign ^ b_sign;

    // Booth 编码 / Wallace 树：24x24 有符号乘积按基-4 Booth 展开为 17 个部分积，
    // 展开到 68 位（Booth 最大左移 32 位），再逐列用 CSA 压成进位保存形式 (s, cout2)
    wire signed [67:0] multiplicand_ext = {36'd0, {8'd0, a_sig}};
    wire signed [34:0] multiplier_ext   = {2'b0, {8'd0, b_sig}, 1'b0};

    wire signed [67:0] partial_products [0:16];
    wire [16:0] switch_outputs [0:67];
    wire [13:0] cout_group [0:67];
    wire  cout  [0:67];
    wire [67:0] cout2;
    wire [67:0] s;

    genvar gi;
    generate
        for (gi = 0; gi < 17; gi = gi + 1) begin : gen_partial_products
            wire [2:0] y_group = {multiplier_ext[gi*2+2],
                                  multiplier_ext[gi*2+1],
                                  multiplier_ext[gi*2]};
            wire signed [67:0] x_shifted = multiplicand_ext << (gi*2);
            wire sel_negative, sel_double_negative, sel_positive, sel_double_positive;
            assign {sel_negative, sel_double_negative, sel_positive, sel_double_positive} =
                {y_group[2] & (y_group[1] ^ y_group[0]), y_group[2] & ~y_group[1] & ~y_group[0],
                 ~y_group[2] & (y_group[1] ^ y_group[0]), ~y_group[2] & y_group[1] & y_group[0]};
            assign partial_products[gi] =
                (sel_negative ? -x_shifted :
                 (sel_double_negative ? (-x_shifted) << 1 :
                  (sel_positive ? x_shifted :
                   (sel_double_positive ? (x_shifted << 1) : 68'sd0))));
        end
    endgenerate

    genvar gj, gk;
    generate
        for (gj = 0; gj < 68; gj = gj + 1) begin : gen_switch
            for (gk = 0; gk < 17; gk = gk + 1) begin
                assign switch_outputs[gj][gk] = partial_products[gk][gj];
            end
        end
    endgenerate

    genvar gl;
    generate
        fma_walloc_17bits u_walloc0 (
            .src_in     (switch_outputs[0]),
            .cin        (14'd0            ),
            .cout_group (cout_group[0]    ),
            .cout       (cout[0]          ),
            .s          (s[0]             )
        );
        assign cout2[0] = cout[0];

        for (gl = 1; gl < 68; gl = gl + 1) begin : gen_wallace
            fma_walloc_17bits u_walloc (
                .src_in     (switch_outputs[gl]),
                .cin        (cout_group[gl-1]  ),
                .cout_group (cout_group[gl]    ),
                .cout       (cout[gl]          ),
                .s          (s[gl]             )
            );
            assign cout2[gl] = cout[gl];
        end
    endgenerate

    // ---------------------------------------------------------------
    // Stage0 -> Stage1 流水寄存器
    // ---------------------------------------------------------------
    reg                p0_valid;
    reg                p0_flushed;
    reg [ID_WIDTH-1:0] p0_id;
    reg         [ 2:0] p0_rm;
    reg                p0_is_special;
    reg         [31:0] p0_sp_result;
    reg         [ 4:0] p0_sp_fflags;
    reg         [67:0] p0_s;
    reg         [67:0] p0_cout2;
    reg signed  [10:0] p0_p_exp;
    reg signed  [10:0] p0_c_lsb;
    reg         [23:0] p0_c_sig;
    reg                p0_p_sign;
    reg                p0_c_sign;
       
    reg                p1_valid;
    reg                p1_flushed;
    reg [ID_WIDTH-1:0] p1_id;
    reg         [ 2:0] p1_rm;
    reg                p1_is_special;
    reg         [31:0] p1_sp_result;
    reg         [ 4:0] p1_sp_fflags;
    reg         [67:0] p1_s;
    reg         [67:0] p1_cout2;
    reg signed  [10:0] p1_p_exp;
    reg signed  [10:0] p1_c_lsb;
    reg         [23:0] p1_c_sig;
    reg                p1_p_sign;
    reg                p1_c_sign;

    function automatic is_younger;
        input [ID_WIDTH-1:0] a;
        input [ID_WIDTH-1:0] b;
        begin
            is_younger = (a != b) &&
                ((a[ID_WIDTH-1] ^ b[ID_WIDTH-1]) ?
                 (a[ID_WIDTH-2:0] < b[ID_WIDTH-2:0]) :
                 (a[ID_WIDTH-2:0] > b[ID_WIDTH-2:0]));
        end
    endfunction

    wire new_flushed = flush && is_younger(issue_id, flush_id);

    always @(posedge clk) begin
        if (rst) begin
            p0_valid     <= 1'b0;
            p0_flushed   <= 1'b0;
            p0_id        <= {ID_WIDTH{1'b0}};
            p0_rm        <= 3'd0;
            p0_is_special<= 1'b0;
            p0_sp_result <= 32'd0;
            p0_sp_fflags <= 5'd0;
            p0_s         <= 68'd0;
            p0_cout2     <= 68'd0;
            p0_p_exp     <= 11'sd0;
            p0_c_lsb     <= 11'sd0;
            p0_c_sig     <= 24'd0;
            p0_p_sign    <= 1'b0;
            p0_c_sign    <= 1'b0;

            p1_valid     <= 1'b0;
            p1_flushed   <= 1'b0;
            p1_id        <= {ID_WIDTH{1'b0}};
            p1_rm        <= 3'd0;
            p1_is_special<= 1'b0;
            p1_sp_result <= 32'd0;
            p1_sp_fflags <= 5'd0;
            p1_s         <= 68'd0;
            p1_cout2     <= 68'd0;
            p1_p_exp     <= 11'sd0;
            p1_c_lsb     <= 11'sd0;
            p1_c_sig     <= 24'd0;
            p1_p_sign    <= 1'b0;
            p1_c_sign    <= 1'b0;
        end else begin
            // stage1 接受 stage0
            p1_valid      <= p0_valid;
            p1_flushed    <= p0_flushed | (flush & p0_valid & is_younger(p0_id, flush_id));
            p1_id         <= p0_id;
            p1_rm         <= p0_rm;
            p1_is_special <= p0_is_special;
            p1_sp_result  <= p0_sp_result;
            p1_sp_fflags  <= p0_sp_fflags;
            p1_s          <= p0_s;
            p1_cout2      <= p0_cout2;
            p1_p_exp      <= p0_p_exp;
            p1_c_lsb      <= p0_c_lsb;
            p1_c_sig      <= p0_c_sig;
            p1_p_sign     <= p0_p_sign;
            p1_c_sign     <= p0_c_sign;

            // stage0 发射新指令
            p0_valid      <= issue_valid;
            p0_flushed    <= issue_valid ? new_flushed : 1'b0;
            p0_id         <= issue_id;
            if (issue_valid) begin
                p0_rm          <= rm;
                p0_is_special  <= is_special;
                p0_sp_result   <= sp_result;
                p0_sp_fflags   <= sp_fflags;
                p0_s           <= s;
                p0_cout2       <= cout2;
                p0_p_exp       <= p_exp;
                p0_c_lsb       <= c_lsb;
                p0_c_sig       <= c_sig;
                p0_p_sign      <= p_sign;
                p0_c_sign      <= c_sign;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage1：合并乘积、宽加法、规范化、舍入、打包
    // ---------------------------------------------------------------
    // 进位保存形式合并为乘积真值；24x24 乘积恒小于 2^48，取低 48 位即可
    wire [68:0] product_sum = {1'b0, p1_s} + {p1_cout2, 1'b0};
    wire [47:0] prod = product_sum[47:0];

    // L：乘积与 c 相加的公共对齐点（取两者 LSB 指数的大者）；
    // 对齐时零操作数不应把公共 LSB 抬升到另一个操作数之上；
    // sh_p/sh_c：各自 LSB 对齐到 L 的右移量，被移出的低位进入 sticky
    wire prod_zero_now = (prod == 48'd0);
    wire c_zero_now    = (p1_c_sig == 24'd0);
    wire signed [10:0] L = c_zero_now  ? p1_p_exp :
                           prod_zero_now ? p1_c_lsb :
                           ((p1_p_exp >= p1_c_lsb) ? p1_p_exp : p1_c_lsb);
    wire [10:0] sh_p = L - p1_p_exp;
    wire [10:0] sh_c = L - p1_c_lsb;

    wire [63:0] p_fixed = (sh_p >= 48) ? 64'd0 :
                          ({16'd0, prod} >> sh_p[5:0]);
    wire [63:0] c_fixed = (sh_c >= 24) ? 64'd0 :
                          ({40'd0, p1_c_sig} >> sh_c[4:0]);

    function automatic or_low128;
        input [127:0] v;
        input [7:0]   cnt;
        integer       i;
        reg           r;
        begin
            r = 1'b0;
            for (i = 0; i < 128; i = i + 1)
                if (i < cnt) r = r | v[i];
            or_low128 = r;
        end
    endfunction

    // 对齐丢弃位：只把“最浅 24 位”按位置保留（frac24，位 i 的指数 = L-1-i），
    // 更深（i<0）的丢弃位才折入 sticky。这样即使丢弃位恰好在 G 位
    // 也能精确表示 RNE 需要区分的中位（G=1,R=0,S=0），不会误当成 sticky。
    function automatic [23:0] drop_p24;
        input [47:0] v;
        input integer sh;
        integer      j;
        integer      i;
        reg  [23:0]  f;
        begin
            f = 24'd0;
            for (j = 0; j < 48; j = j + 1) begin
                if ((j < sh) && v[j]) begin
                    i = j + 24 - sh;
                    if ((i >= 0) && (i < 24))
                        f[i] = 1'b1;
                end
            end
            drop_p24 = f;
        end
    endfunction

    function automatic [23:0] drop_c24;
        input [23:0] v;
        input integer sh;
        integer      j;
        integer      i;
        reg  [23:0]  f;
        begin
            f = 24'd0;
            for (j = 0; j < 24; j = j + 1) begin
                if ((j < sh) && v[j]) begin
                    i = j + 24 - sh;
                    if ((i >= 0) && (i < 24))
                        f[i] = 1'b1;
                end
            end
            drop_c24 = f;
        end
    endfunction

    function automatic drop_p_sticky;
        input [47:0] v;
        input integer sh;
        integer      j;
        integer      i;
        reg          r;
        begin
            r = 1'b0;
            for (j = 0; j < 48; j = j + 1) begin
                if ((j < sh) && v[j]) begin
                    i = j + 24 - sh;
                    if (i < 0)
                        r = 1'b1;
                end
            end
            drop_p_sticky = r;
        end
    endfunction

    function automatic drop_c_sticky;
        input [23:0] v;
        input integer sh;
        integer      j;
        integer      i;
        reg          r;
        begin
            r = 1'b0;
            for (j = 0; j < 24; j = j + 1) begin
                if ((j < sh) && v[j]) begin
                    i = j + 24 - sh;
                    if (i < 0)
                        r = 1'b1;
                end
            end
            drop_c_sticky = r;
        end
    endfunction

    wire [23:0] p_drop_24 = drop_p24(prod, {21'd0, sh_p});
    wire [23:0] c_drop_24 = drop_c24(p1_c_sig, {21'd0, sh_c});
    // 远位丢分（frac24 网格之下的 i<0 位）：不再折叠成“借位+sticky”，
    // 而是按真实权重补到公共网格的最低位段（27 位，位置 0..26）。
    // 只有真正的深度（低于网格最低位）才并入 sticky。
    // 复用 drop_p_sticky/drop_c_sticky 的“i<0”语义不可行（其基准是 frac24），
    // 这里直接按新网格最低位（位置 0，权重 2^(L-51)）计算，
    // far 位 = prod[j]/c_sig[j] 落在位置 0..26，更深即 sticky。
    function automatic [26:0] far_p27;
        input [47:0] v;
        input integer sh;
        integer      j;
        integer      d;
        integer      m;
        reg  [26:0]  f;
        begin
            f = 27'd0;
            m = 51 - sh;
            for (j = 0; j < 48; j = j + 1) begin
                if ((j < (sh - 24)) && v[j]) begin
                    d = j + m;
                    if ((d >= 0) && (d <= 26))
                        f[d] = 1'b1;
                end
            end
            far_p27 = f;
        end
    endfunction
    function automatic [26:0] far_c27;
        input [23:0] v;
        input integer sh;
        integer      j;
        integer      d;
        integer      m;
        reg  [26:0]  f;
        begin
            f = 27'd0;
            m = 51 - sh;
            for (j = 0; j < 24; j = j + 1) begin
                if ((j < (sh - 24)) && v[j]) begin
                    d = j + m;
                    if ((d >= 0) && (d <= 26))
                        f[d] = 1'b1;
                end
            end
            far_c27 = f;
        end
    endfunction
    wire [26:0] far_v_p = far_p27(prod, {21'd0, sh_p});
    wire [26:0] far_v_c = far_c27(p1_c_sig, {21'd0, sh_c});
    // far 位占网格位置 0..26，实际权重最高约 2^27-1，27 位有符号会把
    // bit26=1 的合法正值（如 0x67FCF18）误读成负值（-0x18030E8），
    // 导致 G/R 翻转、RNE 错舍。必须先用 {2'b00,...} 扩到 29 位有符号再取负。
    wire signed [28:0] far_s_p = p1_p_sign ? -$signed({2'b00, far_v_p}) : $signed({2'b00, far_v_p});
    wire signed [28:0] far_s_c = p1_c_sign ? -$signed({2'b00, far_v_c}) : $signed({2'b00, far_v_c});
    // 两项和的取值范围 [-2^28+2, 2^28-2]，29 位有符号 [-2^28, 2^28-1] 可装下。
    wire signed [28:0] far_signed = far_s_p + far_s_c;
    // deep_sticky：低于网格最低位（位置 < 0）的真丢分，恒为纯 sticky。
    // sh_p > 51 表示 prod 的全部 48 位都在 27 位远位区（位置 0..26）之下，
    // 即任何非零位都贡献 sticky；far_c27/far_p27 因 d<0 不会捕获它们。
    wire far_sticky = (sh_p > 51) ? (prod != 48'd0) : 1'b0;
    wire far_sticky_c = (sh_c > 51) ? (p1_c_sig != 24'd0) : 1'b0;

    // 乘积与 c 按符号转为有符号数相加；acc 不再单独取幅值，
    // 直接与带符号的丢弃分数位拼到公共网格后统一求幅值。
    wire signed [66:0] p_signed = p1_p_sign ? -$signed({3'b000, p_fixed})
                                            :  $signed({3'b000, p_fixed});
    wire signed [66:0] c_signed = p1_c_sign ? -$signed({3'b000, c_fixed})
                                            :  $signed({3'b000, c_fixed});
    wire signed [66:0] acc_signed = p_signed + c_signed;

    // 公共对齐字（base = L-51）：acc 与带符号丢弃分数位对齐到同一网格。
    // 丢弃分数位（frac24，指数 L-1-i）不能并入 |acc|：出现抵消时
    // （异号近相等且 c 主导，如 0x3f7fffff + 0xbfffffff）符号会错置，
    // 必须带符号相加后再求幅值，top 才落在正确的前导位（G/R/S 亦正确）。
    // 网格向下扩展 27 位：frac24 落在位置 27..53，远位丢分落在位置 0..26。
    // 这样 ~2^-25 级别的抵消残余（如 (1-2^-24)^2 - 1）的 G/R 位
    // 能精确表达，RNE 的“恰中位”不再被误判为 sticky 而错舍入。
    wire signed [10:0] base = L - 11'sd51;
    // 注意：sdp/sdc 必须按 27 位带符号宽处理（先把 p_drop_24 扩到 27 位再做负号）——
    // 若先算成 25 位负值再用 {1'b0, sdp} 并到 26 位，会是零扩展，丢掉符号位，
    // 负丢弃位会变成正的（如 -0x800000 错加成 +0x1800000），full 的 top/GRS 全错。
    wire signed [26:0] sdp = p1_p_sign ? -$signed({3'b000, p_drop_24})
                                       :  $signed({3'b000, p_drop_24});
    wire signed [26:0] sdc = p1_c_sign ? -$signed({3'b000, c_drop_24})
                                       :  $signed({3'b000, c_drop_24});
    wire signed [26:0] drop_signed = sdp + sdc;
    wire signed [117:0] acc_shl = {acc_signed, 51'd0};
    wire signed [117:0] full_signed = acc_shl +
                                      $signed({{64{drop_signed[26]}}, drop_signed, 27'd0}) +
                                      $signed({{89{far_signed[28]}}, far_signed});
    wire acc_sign = full_signed[117];
    wire [117:0] full_mag = acc_sign ? (~full_signed + 118'd1) : full_signed;
    // 精确的带符号和已把远位丢分的借位/进位都并进幅值，无需 far_borrow
    wire [117:0] full = full_mag;

    // 深位残差（指数 < base，处于整个网格之下）的舍入方向符号。
    // 深移只能发生在单一操作数（L = max(p_exp,c_lsb)，另一操作数 sh=0），
    // 因此残差的净符号明确：相对幅值“正向”当且仅当该操作数符号与 acc_sign 相同。
    // 精确平局（G=1,R=0,网格内 S=0）时 RNE 必须按残差符号决定向上/向下，
    // 否则无符号 sticky 会把“略低于中点”误判成“略高于中点”而错舍入。
    wire deep_exists = far_sticky | far_sticky_c;
    wire deep_pos    = (far_sticky   & (p1_p_sign == acc_sign)) |
                       (far_sticky_c & (p1_c_sign == acc_sign));

// 统一字前导零计数：top 为 full 最高位相对 base 的指数（0..117）
    function automatic [6:0] clz118;
        input [117:0] v;
        reg           found;
        integer       i;
        begin
            found = 1'b0;
            clz118 = 7'd118;
            for (i = 117; i >= 0; i = i - 1) begin
                if (!found && v[i]) begin
                    clz118 = 7'd117 - i[6:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    wire acc_zero = (full == 118'd0);
    wire [6:0] lz_full = clz118(full);
    wire [6:0] top = 7'd117 - lz_full;

`ifdef ENABLE_FMA_DEBUG
    integer dbg_cnt;
    always @(posedge clk) begin
        if (p1_valid) begin
            dbg_cnt <= dbg_cnt + 1;
            if (dbg_cnt >= 1088 && dbg_cnt <= 1094) begin
            $display("FMA %0d L=%0d base=%0d sh_p=%0d sh_c=%0d prod=%h pfixed=%h cfsig=%h acc=%h csig=%h drop=%h far=%h full=%h fmag=%h top=%0d n_s=%b fstk=%b fstkc=%b n_g=%b n_r=%b n_sig=%h n_exp=%0d n_iex=%b n_res=%h",
                     dbg_cnt+1, L, base, sh_p, sh_c, prod, p_fixed, c_fixed,
                     acc_signed, p1_c_sig, drop_signed, far_signed, full_signed,
                     full_mag, top, norm_s, far_sticky, far_sticky_c, norm_g, norm_r,
                     norm_sig_r, norm_exp, norm_inexact, norm_result);
            end
        end
    end
`endif

    // 结果为零时符号按 IEEE 规则：乘积与 c 同号取该号，异号且 RDN 时为负
    wire zero_sign = (p1_p_sign == p1_c_sign) ? p1_p_sign : (p1_rm == `RDN);

    // 次正规结果路径：把 full 的 24 位有效数窗口下移到 LSB 指数 2^-149。
    //   sub_d = -149 - base：所需的右移量（full 的 LSB 指数为 base）
    //   sub_u_wire：移位后窗口的 24 位（bit0 指数 = -149）
    //   sub_g/r/s：窗口以下被移出的舍入位，统一按位置从 full 提取
    wire signed [13:0] sub_d = -14'sd149 - $signed({{3{base[10]}}, base});
    wire signed [13:0] sub_d_abs = (sub_d < 0) ? -sub_d : sub_d;
    wire [6:0] sub_shift = (sub_d_abs > 14'sd117) ? 7'd117 : sub_d_abs[6:0];

    wire [23:0] sub_u_wire;
    wire [117:0] sub_shift_r = full >> sub_shift;
    assign sub_u_wire = (sub_d_abs == 0) ? full[23:0] :
                        ((sub_d_abs > 14'sd117) ? 24'd0 : sub_shift_r[23:0]);
    wire sub_g_wire = (sub_d_abs == 0) ? 1'b0 :
                      full[sub_shift - 7'd1];
    wire sub_r_wire = (sub_d_abs < 14'sd2) ? 1'b0 :
                      full[sub_shift - 7'd2];
    wire sub_s_wire = far_sticky | far_sticky_c |
                      ((sub_d_abs < 14'sd3) ? 1'b0 :
                       ((sub_d_abs > 14'sd117) ? or_low128({10'd0, full}, 8'd118) :
                        or_low128({10'd0, full}, sub_shift - 7'd2)));

    // 网格内（full 中、R 位之下）的 sticky，不含深位残差；
    // 仅 sub_d_abs <= 117 时 G/R/S 相对窗口定义有效
    wire [7:0] sub_s_cnt = (sub_shift >= 7'd2) ? (sub_shift - 7'd2) : 8'd0;
    wire sub_s_grid = (sub_d_abs <= 14'sd117) ?
                      ((sub_shift >= 7'd2) ? or_low128({10'd0, full}, sub_s_cnt) : 1'b0) :
                      1'b0;
    // RNE 精确平局 + 深位残差：按残差相对幅值方向决定舍入
    wire sub_tie_rne = (p1_rm == `RNE) & sub_g_wire & ~sub_r_wire &
                       ~sub_s_grid & deep_exists;

    wire sub_round_up_frm;
    wire sub_inexact;
    frm u_sub_frm (
        .rm      (p1_rm),
        .sign    (acc_sign),
        .lsb     (sub_u_wire[0]),
        .guard   (sub_g_wire),
        .round   (sub_r_wire),
        .sticky  (sub_s_wire),
        .round_up(sub_round_up_frm),
        .inexact (sub_inexact)
    );
    wire sub_round_up = sub_tie_rne ? deep_pos : sub_round_up_frm;

    wire [24:0] sub_rounded_wire = {1'b0, sub_u_wire} + {24'd0, sub_round_up};
    wire sub_to_normal = sub_rounded_wire[23];
    wire sub_zero_out  = (sub_rounded_wire == 25'd0);

    reg [31:0] sub_result;
    reg [4:0]  sub_fflags;
    always @(*) begin
        sub_result = 32'd0;
        sub_fflags = 5'd0;
        // 舍入后 24 位溢出 -> 进位为最小正规数（指数域 1）；
        // 否则按次正规格式打包（指数域 0，尾数取低 23 位）
        if (sub_to_normal) begin
            sub_result = {acc_sign, 8'd1, 23'd0};
        end else if (sub_zero_out) begin
            sub_result = {acc_sign, 31'd0};
        end else begin
            sub_result = {acc_sign, 8'd0, sub_rounded_wire[22:0]};
        end
        // 次正规结果舍入不精确时置 NX；仅当舍入后仍为次正规/零时才置 UF
        // （舍入进位到最小正规数属“舍入后非微小”, 按 after-rounding tininess 不下溢）
        if (sub_inexact) begin
            sub_fflags[`NX] = 1'b1;
            if (~sub_to_normal)
                sub_fflags[`UF] = 1'b1;
        end
    end

    // 正规数 G/R/S 与舍入（top 为 full 最高位相对 base 的指数，无偏指数 = base+top）
    reg [23:0] norm_sig_r;
    reg        norm_g, norm_r, norm_s;
    reg signed [12:0] norm_exp;
    // 移位量由 top 推导，避免在 always 内形成组合环
    wire [ 6:0] norm_sh_r = (top >= 7'd23) ? (top - 7'd23) : 7'd0;
    wire [ 6:0] norm_sh_l = (top < 7'd23)  ? (7'd23 - top)  : 7'd0;
    wire [117:0] norm_shift_r = full >> norm_sh_r;
    wire [117:0] norm_shift_l = full << norm_sh_l;
    always @(*) begin
        norm_sig_r = 24'd0;
        norm_g     = 1'b0;
        norm_r     = 1'b0;
        norm_s     = far_sticky | far_sticky_c;
        norm_exp   = $signed({{2{base[10]}}, base}) + $signed({6'b0, top});
        if (top >= 7'd23) begin
            // 右移：G/R/S 直接取窗口下方的 full 位置位
            norm_sig_r = norm_shift_r[23:0];
            if (top >= 7'd24) begin
                norm_g = full[top - 7'd24];
                if (top >= 7'd25) begin
                    norm_r = full[top - 7'd25];
                    if (top >= 7'd26)
                        norm_s = far_sticky | far_sticky_c |
                                 or_low128({10'd0, full}, top - 7'd25);
                end
            end
        end else begin
            // 左移对齐：无移出的分数位，仅剩余下更深处的 sticky
            norm_sig_r = norm_shift_l[23:0];
            norm_g     = 1'b0;
            norm_r     = 1'b0;
            norm_s     = far_sticky | far_sticky_c;
        end
    end

    // 网格内（full 中、R 位之下）的 sticky，不含深位残差
    wire norm_s_grid = (top >= 7'd26) ? or_low128({10'd0, full}, top - 7'd25) : 1'b0;
    // RNE 精确平局 + 深位残差：按残差相对幅值方向决定舍入（见 deep_pos 注释）
    wire norm_tie_rne = (p1_rm == `RNE) & norm_g & ~norm_r &
                        ~norm_s_grid & deep_exists;

    wire norm_round_up_frm;
    wire norm_inexact;
    frm u_norm_frm (
        .rm      (p1_rm),
        .sign    (acc_sign),
        .lsb     (norm_sig_r[0]),
        .guard   (norm_g),
        .round   (norm_r),
        .sticky  (norm_s),
        .round_up(norm_round_up_frm),
        .inexact (norm_inexact)
    );
    wire norm_round_up = norm_tie_rne ? deep_pos : norm_round_up_frm;

    wire [24:0] norm_sig_rounded = {1'b0, norm_sig_r} + {24'd0, norm_round_up};
    wire [24:0] norm_sig_final = norm_sig_rounded[24] ? 25'h1800000 :
                                 {1'b0, norm_sig_rounded[23:0]};
    wire signed [12:0] norm_exp_final = norm_exp + (norm_sig_rounded[24] ? 13'sd1 : 13'sd0);

    reg [31:0] norm_result;
    reg [4:0]  norm_fflags;
    always @(*) begin
        norm_result = 32'd0;
        norm_fflags = 5'd0;
        // 指数超出 float 范围：上溢为 Inf，置 OF 与 NX；
        // 否则打包：符号 | 无偏指数 + bias(127) | 有效数小数部分
        if (norm_exp_final > 13'sd127) begin
            norm_result = {acc_sign, 8'hFF, 23'd0};
            norm_fflags[`OF] = 1'b1;
            norm_fflags[`NX] = 1'b1;   // 上溢舍入恒不精确(结果 != 精确值), 即使 G/R/S 全 0
        end else begin
            norm_result = {acc_sign, norm_exp_final[7:0] + 8'd127,
                           norm_sig_final[22:0]};
            norm_fflags[`NX] = norm_inexact;
        end
    end

    // 选择正规 / 次正规：结果为 0 按 zero_sign 打包（+0/-0），
    // 无偏指数 < -126 走次正规路径，否则走正规路径
    reg [31:0] finite_final_result;
    reg [4:0]  finite_final_fflags;
    always @(*) begin
        if (acc_zero) begin
            finite_final_result = {zero_sign, 31'd0};
            finite_final_fflags = 5'd0;
        end else if (norm_exp < -13'sd126) begin
            finite_final_result = sub_result;
            finite_final_fflags = sub_fflags;
        end else begin
            finite_final_result = norm_result;
            finite_final_fflags = norm_fflags;
        end
    end

    // 写回：stage1 的合法条目（未被 flush 冲刷）直接输出，
    // 特殊路径的结果与标志绕过数值通路
    assign wb_valid   = p1_valid & ~p1_flushed;
    assign wb_id      = p1_id;
    assign wb_result  = p1_is_special ? p1_sp_result : finite_final_result;
    assign wb_fflags  = p1_is_special ? p1_sp_fflags : finite_final_fflags;

endmodule

/* verilator lint_off DECLFILENAME */
// 单列 17 个部分积位的 CSA 压缩：17 输入 + 上列进位 -> (cout, s) + 进位组传下列
module fma_walloc_17bits(
    input [16:0] src_in,
    input [13:0] cin,
    output [13:0] cout_group,
    output cout, s
);
    wire [13:0] c;
    wire [4:0] first_s;
    fma_csa csa0 (.in (src_in[16:14]),.cout (c[4]),.s (first_s[4]) );
    fma_csa csa1 (.in (src_in[13:11]),.cout (c[3]),.s (first_s[3]) );
    fma_csa csa2 (.in (src_in[10:08]),.cout (c[2]),.s (first_s[2]) );
    fma_csa csa3 (.in (src_in[07:05]),.cout (c[1]),.s (first_s[1]) );
    fma_csa csa4 (.in (src_in[04:02]),.cout (c[0]),.s (first_s[0]) );
    wire [3:0] secnod_s;
    fma_csa csa5 (.in ({first_s[4:2]}),.cout (c[8]),.s (secnod_s[3]));
    fma_csa csa6 (.in ({first_s[1:0],src_in[1]}),.cout (c[7]),.s (secnod_s[2]));
    fma_csa csa7 (.in ({src_in[0],cin[4:3]}),.cout (c[6]),.s (secnod_s[1]));
    fma_csa csa8 (.in ({cin[2:0]}),.cout (c[5]),.s (secnod_s[0]));
    wire [1:0] thrid_s;
    fma_csa csa9 (.in (secnod_s[3:1]),.cout (c[10]),.s (thrid_s[1]));
    fma_csa csaA (.in ({secnod_s[0],cin[6:5]}),.cout (c[09]),.s (thrid_s[0]));
    wire [1:0] fourth_s;
    fma_csa csaB (.in ({thrid_s[1:0],cin[10]}),.cout (c[12]),.s (fourth_s[1]));
    fma_csa csaC (.in ({cin[9:7]}),.cout (c[11]),.s (fourth_s[0]));
    wire fifth_s;
    fma_csa csaD (.in ({fourth_s[1:0],cin[11]}),.cout (c[13]),.s (fifth_s));
    fma_csa csaE (.in ({fifth_s,cin[13:12]}),.cout (cout),.s (s));
    assign cout_group = c;
endmodule

// 3:2 全加器
module fma_csa(
    input [2:0] in,
    output cout, s
);
    wire a,b,cin;
    assign a = in[2];
    assign b = in[1];
    assign cin = in[0];
    assign s = a ^ b ^ cin;
    assign cout = a & b | b & cin | a & cin;
endmodule
