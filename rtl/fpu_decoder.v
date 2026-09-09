// (-1)^s * 1.fraction * 2^(exponent-127) --> (-1)^s * sig * 2^exp

module fpu_decoder (
    input  wire [31:0] a,        // 单精度输入

    output wire        sign,     // 符号位
    output wire [ 8:0] exp,      // 有符号无偏指数，仅对 normal/subnormal 有效
    output wire [23:0] sig,      // 统一有效数：1.xxx，bit23 为显式前导 1

    // 类型分类标志
    output wire        is_zero,
    output wire        is_subnormal,
    output wire        is_normal,
    output wire        is_inf,
    output wire        is_nan,
    output wire        is_snan,   // signaling NaN
    output wire        is_qnan    // quiet NaN
);

    wire        s = a[31];
    wire [ 7:0] e = a[30:23];
    wire [22:0] f = a[22:0];

    assign is_zero      = (e == 8'h00) && (f == 23'h000000);
    assign is_subnormal = (e == 8'h00) && (f != 23'h000000);
    assign is_normal    = (e != 8'h00) && (e != 8'hFF);
    assign is_inf       = (e == 8'hFF) && (f == 23'h000000);
    assign is_nan       = (e == 8'hFF) && (f != 23'h000000);

    // 单精度中 fraction 最高位 bit22 为 quiet bit（1=QNaN, 0=SNaN）
    assign is_snan      = is_nan && (f[22] == 1'b0);
    assign is_qnan      = is_nan && (f[22] == 1'b1);

    // 前导零计算
    function automatic [4:0] leading_zeros;
        input [22:0] v;
        reg          found;
        integer      i;
        begin
            found = 1'b0;
            leading_zeros = 5'd23;
            for (i = 22; i >= 0; i = i - 1) begin
                if (!found) begin
                    if (v[i]) begin
                        leading_zeros = 5'd22 - i[4:0];
                        found = 1'b1;
                    end
                end
            end
        end
    endfunction

    wire [4:0] lead_zero = leading_zeros(f);

    // normal 有效数：1.fraction
    wire [23:0] sig_normal = {1'b1, f};

    // subnormal 规范化
    wire [23:0] sig_subnormal = {1'b0, f} << (lead_zero + 5'd1);

    wire signed [8:0] e_signed     = {1'b0, e};
    wire signed [8:0] lz_signed    = {4'b0000, lead_zero};

    wire signed [8:0] exp_normal    = e_signed - 9'sd127;
    wire signed [8:0] exp_subnormal = -9'sd127 - lz_signed;

    assign sign = s;
    assign sig  = is_normal    ? sig_normal    :
                  is_subnormal ? sig_subnormal :
                  24'd0;

    assign exp  = is_normal    ? exp_normal    :
                  is_subnormal ? exp_subnormal :
                  9'sd0;

endmodule
