// FPU 测试台公用工具
// 将 IEEE-754 single 位型转换为 double 位型，以便用 $bitstoreal() 打印十进制。

`ifndef FPU_TB_UTIL_VH
`define FPU_TB_UTIL_VH

function automatic [63:0] single_to_double;
    input [31:0] v;
    reg [7:0]  e;
    reg [22:0] f;
    reg [4:0]  clz;
    reg [4:0]  msb;
    integer    i;
    begin
        e = v[30:23];
        f = v[22:0];

        if (e == 8'hff) begin
            if (f == 23'b0)
                single_to_double = {v[31], 11'h7ff, 52'b0};
            else
                single_to_double = {v[31], 11'h7ff, 1'b1, f[21:0], 29'b0};
        end else if (e == 8'h00) begin
            if (f == 23'b0) begin
                single_to_double = {v[31], 63'b0};
            end else begin
                clz = 5'd0;
                for (i = 22; i >= 0; i = i - 1) begin
                    if (!f[i])
                        clz = clz + 5'd1;
                    else
                        i = -1;
                end
                msb = 6'd22 - clz;
                single_to_double = {v[31], {1'b0, msb} + 11'd874,
                                    {29'b0, f} << (6'd52 - msb)};
            end
        end else begin
            single_to_double = {v[31], {3'b0, e} + 11'd896, {29'b0, f} << 6'd29};
        end
    end
endfunction

`endif
