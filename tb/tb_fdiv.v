`include "fpu_config.vh"
`include "fpu_tb_util.vh"

//////////////////////////////////////////////////////////////////////////////
//
// tb_fdiv - fdiv 单元测试(占位)
//
// 注意: rtl/fdiv.v 尚未实现, 本测试定义了 fdiv 单元的预期接口
//   (与 fma_unit 一致的风格: fpu_decoder 解包源操作数 + issue/wb 握手),
//   待 fdiv.v 实现后, tb/Makefile 会自动把本测试纳入编译。
//   接口:
//     module fdiv #(parameter ID_WIDTH = 5) (
//       input  clk, rst,
//       input  issue_valid, issue_id[ID_WIDTH-1:0], op[6:0], rm[2:0],
//       input  s1_sign, s1_exp[8:0](signed), s1_sig[23:0],
//              s1_zero, s1_inf, s1_nan, s1_snan,
//       input  s2_sign, s2_exp[8:0](signed), s2_sig[23:0],
//              s2_zero, s2_inf, s2_nan, s2_snan,
//       input  flush, flush_id[ID_WIDTH-1:0],
//       output wb_valid, wb_id[ID_WIDTH-1:0], wb_result[31:0], wb_fflags[4:0]
//     );
//
// 覆盖:
//   FDIV_S: 普通数精确/不精确、零、Inf、NaN、DZ/NV/NX 标志
//
//////////////////////////////////////////////////////////////////////////////

module tb_fdiv;
    localparam ID_WIDTH = 5;

    // fflags 位序与 rtl/fpu_config.vh 保持一致: NV=4 DZ=3 OF=2 UF=1 NX=0
    localparam [4:0] FL_NV = (1 << `NV);
    localparam [4:0] FL_DZ = (1 << `DZ);
    localparam [4:0] FL_OF = (1 << `OF);
    localparam [4:0] FL_UF = (1 << `UF);
    localparam [4:0] FL_NX = (1 << `NX);

    reg clk;
    reg rst;

    reg                 issue_valid;
    reg [ID_WIDTH-1:0]  issue_id;
    reg [6:0]           op;
    reg [2:0]           rm;
    reg [31:0]          src1;
    reg [31:0]          src2;
    reg                 flush;
    reg [ID_WIDTH-1:0]  flush_id;

    wire                 wb_valid;
    wire [ID_WIDTH-1:0]  wb_id;
    wire [31:0]          wb_result;
    wire [4:0]           wb_fflags;

    reg [31:0] exp_result;
    reg [4:0]  exp_fflags;
    reg        exp_pending;
    reg [ID_WIDTH-1:0] exp_id;
    integer    errors;
    integer    tests;

    // 与 fma_unit 一致的约定: 先解包再送入 fdiv
    wire               s1_sign, s2_sign;
    wire signed [ 8:0] s1_exp , s2_exp ;
    wire        [23:0] s1_sig , s2_sig ;
    wire               s1_zero, s2_zero;
    wire               s1_inf , s2_inf ;
    wire               s1_nan , s2_nan ;
    wire               s1_snan, s2_snan;

    fpu_decoder u_dec1 (.a(src1), .sign(s1_sign), .exp(s1_exp), .sig(s1_sig),
                        .is_zero(s1_zero), .is_inf(s1_inf),
                        .is_nan(s1_nan), .is_snan(s1_snan));
    fpu_decoder u_dec2 (.a(src2), .sign(s2_sign), .exp(s2_exp), .sig(s2_sig),
                        .is_zero(s2_zero), .is_inf(s2_inf),
                        .is_nan(s2_nan), .is_snan(s2_snan));

    fdiv #(.ID_WIDTH(ID_WIDTH)) u_dut (
        .clk        (clk),
        .rst        (rst),
        .issue_valid(issue_valid),
        .issue_id   (issue_id),
        .op         (op),
        .rm         (rm),
        .s1_sign    (s1_sign),
        .s1_exp     (s1_exp),
        .s1_sig     (s1_sig),
        .s1_zero    (s1_zero),
        .s1_inf     (s1_inf),
        .s1_nan     (s1_nan),
        .s1_snan    (s1_snan),
        .s2_sign    (s2_sign),
        .s2_exp     (s2_exp),
        .s2_sig     (s2_sig),
        .s2_zero    (s2_zero),
        .s2_inf     (s2_inf),
        .s2_nan     (s2_nan),
        .s2_snan    (s2_snan),
        .flush      (flush),
        .flush_id   (flush_id),
        .wb_valid   (wb_valid),
        .wb_id      (wb_id),
        .wb_result  (wb_result),
        .wb_fflags  (wb_fflags)
    );

    always #5 clk = ~clk;

    task check_result;
        input [31:0] exp_r;
        input [4:0]  exp_f;
        input [ID_WIDTH-1:0] exp_i;
        reg pass;
        begin
            pass = (wb_result === exp_r) && (wb_fflags === exp_f) && (wb_id === exp_i);
            $display("  Retire [%0d] result=0x%08h fflags=0x%02h    %s",
                     wb_id, wb_result, wb_fflags, pass ? "PASS" : "FAIL");
            if (!pass) begin
                $display("  Expected result=0x%08h fflags=0x%02h id=%0d",
                         exp_r, exp_f, exp_i);
                errors = errors + 1;
            end
            tests  = tests + 1;
            exp_pending = 1'b0;
        end
    endtask

    task run_one;
        input [31:0] a;
        input [31:0] b;
        input [31:0] exp_r;
        input [4:0]  exp_f;
        input [ID_WIDTH-1:0] id_in;
        integer issue_t;
        integer latency;
        begin
            if (exp_pending) begin
                $display("FAIL: previous instruction not retired");
                errors = errors + 1;
            end

            @(negedge clk);
            #1;
            issue_valid = 1'b1;
            issue_id    = id_in;
            op          = `FDIV_S;
            rm          = `RNE;
            src1        = a;
            src2        = b;
            flush       = 1'b0;
            flush_id    = 5'b0;

            exp_result  = exp_r;
            exp_fflags  = exp_f;
            exp_id      = id_in;
            exp_pending = 1'b1;
            issue_t     = $time;

            $display("Issue [%0d] FDIV    %g / %g           rm=RNE", id_in,
                     $bitstoreal(single_to_double(a)),
                     $bitstoreal(single_to_double(b)));

            #10;                     // 保持一拍，在下一个下降沿释放
            issue_valid = 1'b0;

            while (!wb_valid)
                #10;

            #1;
            latency = ($time - issue_t) / 10;
            $display("  Cycle [%0d]: latency=%0d cycles, retire_time=%0t",
                     id_in, latency, $time);
            check_result(exp_result, exp_fflags, exp_id);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        issue_valid = 1'b0;
        issue_id    = 5'b0;
        op          = 7'd0;
        rm          = `RNE;
        src1        = 32'd0;
        src2        = 32'd0;
        flush       = 1'b0;
        flush_id    = 5'b0;
        errors      = 0;
        tests       = 0;
        exp_pending = 1'b0;

        $dumpfile("tb_fdiv.vcd");
        $dumpvars(0, tb_fdiv);

        #5 rst = 1'b0;
        #10;

        // 6 / 2 = 3
        run_one(32'h40c00000, 32'h40000000, 32'h40400000, 5'd0, 5'd0);
        // 1 / 2 = 0.5
        run_one(32'h3f800000, 32'h40000000, 32'h3f000000, 5'd0, 5'd1);
        // -6 / 2 = -3
        run_one(32'hc0c00000, 32'h40000000, 32'hc0400000, 5'd0, 5'd2);
        // 1 / 0 -> +Inf + DZ
        run_one(32'h3f800000, 32'h00000000, 32'h7f800000, FL_DZ, 5'd3);
        // -1 / 0 -> -Inf + DZ
        run_one(32'hbf800000, 32'h00000000, 32'hff800000, FL_DZ, 5'd4);
        // 0 / 0 -> canonical NaN + NV
        run_one(32'h00000000, 32'h00000000, 32'h7fc00000, FL_NV, 5'd5);
        // Inf / Inf -> canonical NaN + NV
        run_one(32'h7f800000, 32'h7f800000, 32'h7fc00000, FL_NV, 5'd6);
        // 0 / 3 = 0
        run_one(32'h00000000, 32'h40400000, 32'h00000000, 5'd0, 5'd7);
        // 1 / Inf = 0
        run_one(32'h3f800000, 32'h7f800000, 32'h00000000, 5'd0, 5'd8);
        // NaN / 1 -> canonical NaN
        run_one(32'h7fc00001, 32'h3f800000, 32'h7fc00000, 5'd0, 5'd9);
        // 1 / 3 = 0x3eaaaaab (RNE, 不精确 + NX)
        run_one(32'h3f800000, 32'h40400000, 32'h3eaaaaab, FL_NX, 5'd10);
        // 2 / 3 = 0x3f2aaaab (RNE, 不精确 + NX)
        run_one(32'h40000000, 32'h40400000, 32'h3f2aaaab, FL_NX, 5'd11);

        $display("============================================");
        $display("fdiv tests finished: %0d passed, %0d errors", tests, errors);
        $display("  waveform: tb_fdiv.vcd");
        $display("============================================");
        if (errors)
            $finish(1);
        else
            $finish(0);
    end

endmodule
