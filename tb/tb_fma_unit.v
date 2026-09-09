`include "fpu_config.vh"
`include "fpu_tb_util.vh"

//////////////////////////////////////////////////////////////////////////////
//
// tb_fma_unit - fma_unit 单元测试
//
// 覆盖：
//   FADD / FSUB / FMUL / FMADD / FMSUB / FNMADD / FNMSUB
//   普通数、零、次正规数、Inf / NaN、舍入标志的基础用例
//
// 时序约定：
//   在下降沿后 1ns 拉高 issue_valid，保持一个周期；
//   然后等待 wb_valid 置位，检查结果。
//
//////////////////////////////////////////////////////////////////////////////

module tb_fma_unit;
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
    reg [31:0]          src3;
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

    // 与 fpu 顶层一致：先解包再送入 fma_unit（单元测试覆盖 fma_unit 本身）
    wire               s1_sign, s2_sign, s3_sign;
    wire signed [ 8:0] s1_exp , s2_exp , s3_exp ;
    wire        [23:0] s1_sig , s2_sig , s3_sig ;
    wire               s1_zero, s2_zero, s3_zero;
    wire               s1_inf , s2_inf , s3_inf ;
    wire               s1_nan , s2_nan , s3_nan ;
    wire               s1_snan, s2_snan, s3_snan;

    fpu_decoder u_dec1 (.a(src1), .sign(s1_sign), .exp(s1_exp), .sig(s1_sig),
                        .is_zero(s1_zero), .is_inf(s1_inf),
                        .is_nan(s1_nan), .is_snan(s1_snan));
    fpu_decoder u_dec2 (.a(src2), .sign(s2_sign), .exp(s2_exp), .sig(s2_sig),
                        .is_zero(s2_zero), .is_inf(s2_inf),
                        .is_nan(s2_nan), .is_snan(s2_snan));
    fpu_decoder u_dec3 (.a(src3), .sign(s3_sign), .exp(s3_exp), .sig(s3_sig),
                        .is_zero(s3_zero), .is_inf(s3_inf),
                        .is_nan(s3_nan), .is_snan(s3_snan));

    fma_unit #(.ID_WIDTH(ID_WIDTH)) u_dut (
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
        .s3_sign    (s3_sign),
        .s3_exp     (s3_exp),
        .s3_sig     (s3_sig),
        .s3_zero    (s3_zero),
        .s3_inf     (s3_inf),
        .s3_nan     (s3_nan),
        .s3_snan    (s3_snan),
        .flush      (flush),
        .flush_id   (flush_id),
        .wb_valid   (wb_valid),
        .wb_id      (wb_id),
        .wb_result  (wb_result),
        .wb_fflags  (wb_fflags)
    );

    always #5 clk = ~clk;

    task print_issue;
        input [6:0] op_in;
        input [2:0] rm_in;
        input [31:0] a;
        input [31:0] b;
        input [31:0] c;
        input [ID_WIDTH-1:0] id_in;
        begin
            case (op_in)
                `FADD_S:   $display("Issue [%0d] FADD    %g + %g           rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)), rm_in);
                `FSUB_S:   $display("Issue [%0d] FSUB    %g - %g           rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)), rm_in);
                `FMUL_S:   $display("Issue [%0d] FMUL    %g * %g           rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)), rm_in);
                `FMADD_S:  $display("Issue [%0d] FMADD   %g * %g + %g    rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)), rm_in);
                `FMSUB_S:  $display("Issue [%0d] FMSUB   %g * %g - %g    rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)), rm_in);
                `FNMADD_S: $display("Issue [%0d] FNMADD  -(%g * %g) + %g rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)), rm_in);
                `FNMSUB_S: $display("Issue [%0d] FNMSUB  -(%g * %g) - %g rm=%0d", id_in,
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)), rm_in);
                default:   $display("Issue [%0d] op=%0d", id_in, op_in);
            endcase
        end
    endtask

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
        input [6:0] op_in;
        input [2:0] rm_in;
        input [31:0] a;
        input [31:0] b;
        input [31:0] c;
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
            op          = op_in;
            rm          = rm_in;
            src1        = a;
            src2        = b;
            src3        = c;
            flush       = 1'b0;
            flush_id    = 5'b0;

            exp_result  = exp_r;
            exp_fflags  = exp_f;
            exp_id      = id_in;
            exp_pending = 1'b1;
            issue_t     = $time;

            print_issue(op_in, rm_in, a, b, c, id_in);

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
        src3        = 32'd0;
        flush       = 1'b0;
        flush_id    = 5'b0;
        errors      = 0;
        tests       = 0;
        exp_pending = 1'b0;

        $dumpfile("tb_fma_unit.vcd");
        $dumpvars(0, tb_fma_unit);

        #5 rst = 1'b0;
        #10;

        // FADD: 1 + 2 = 3
        run_one(`FADD_S, `RNE, 32'h3f800000, 32'h40000000, 32'h00000000,
                32'h40400000, 5'd0, 5'd0);
        // FADD: 1 + (-1) = +0 (RNE)
        run_one(`FADD_S, `RNE, 32'h3f800000, 32'hbf800000, 32'h00000000,
                32'h00000000, 5'd0, 5'd1);
        // FSUB: 1 - 1 = +0
        run_one(`FSUB_S, `RNE, 32'h3f800000, 32'h3f800000, 32'h00000000,
                32'h00000000, 5'd0, 5'd2);
        // FMUL: 2 * 3 = 6
        run_one(`FMUL_S, `RNE, 32'h40000000, 32'h40400000, 32'h00000000,
                32'h40c00000, 5'd0, 5'd3);
        // FMUL: -2 * 3 = -6
        run_one(`FMUL_S, `RNE, 32'hc0000000, 32'h40400000, 32'h00000000,
                32'hc0c00000, 5'd0, 5'd4);
        // FMADD: 2 * 3 + 4 = 10
        run_one(`FMADD_S, `RNE, 32'h40000000, 32'h40400000, 32'h40800000,
                32'h41200000, 5'd0, 5'd5);
        // FMSUB: 2 * 3 - 4 = 2
        run_one(`FMSUB_S, `RNE, 32'h40000000, 32'h40400000, 32'h40800000,
                32'h40000000, 5'd0, 5'd6);
        // FNMADD: -(2 * 3) + 4 = -2
        run_one(`FNMADD_S, `RNE, 32'h40000000, 32'h40400000, 32'h40800000,
                32'hc0000000, 5'd0, 5'd7);
        // FNMSUB: -(2 * 3) - 4 = -10
        run_one(`FNMSUB_S, `RNE, 32'h40000000, 32'h40400000, 32'h40800000,
                32'hc1200000, 5'd0, 5'd8);
        // FADD: 最小次正规数 + 自身 = 2 * min_sub
        run_one(`FADD_S, `RNE, 32'h00000001, 32'h00000001, 32'h00000000,
                32'h00000002, 5'd0, 5'd9);
        // FMUL: 最小次正规数 * 1.0 = 最小次正规数
        run_one(`FMUL_S, `RNE, 32'h00000001, 32'h3f800000, 32'h00000000,
                32'h00000001, 5'd0, 5'd10);
        // FMUL: 0 * Inf -> canonical NaN + NV
        run_one(`FMUL_S, `RNE, 32'h00000000, 32'h7f800000, 32'h00000000,
                32'h7fc00000, FL_NV, 5'd11);
        // FADD: Inf + (-Inf) -> canonical NaN + NV
        run_one(`FADD_S, `RNE, 32'h7f800000, 32'hff800000, 32'h00000000,
                32'h7fc00000, FL_NV, 5'd12);
        // FADD: NaN + 1 -> canonical NaN
        run_one(`FADD_S, `RNE, 32'h7fc00001, 32'h3f800000, 32'h00000000,
                32'h7fc00000, 5'd0, 5'd13);
        // FMUL: Inf * 2 -> +Inf
        run_one(`FMUL_S, `RNE, 32'h7f800000, 32'h40000000, 32'h00000000,
                32'h7f800000, 5'd0, 5'd14);

        // 连续发射两个 FMUL，验证流水线不阻塞
        @(negedge clk);
        #1;
        issue_valid = 1'b1;
        issue_id    = 5'd15;
        op          = `FMUL_S;
        rm          = `RNE;
        src1        = 32'h40000000;
        src2        = 32'h40400000;
        src3        = 32'h00000000;
        print_issue(op, rm, src1, src2, src3, issue_id);
        #10;   // 发射第一条
        issue_id    = 5'd16;
        src1        = 32'h40400000;
        src2        = 32'h40800000;
        print_issue(op, rm, src1, src2, src3, issue_id);
        #10;   // 发射第二条
        issue_valid = 1'b0;

        while (!wb_valid || wb_id != 5'd15)
            #10;
        #1;
        $display("  Cycle [%0d]: latency=2 cycles", 5'd15);
        check_result(32'h40c00000, 5'd0, 5'd15);

        while (!wb_valid || wb_id != 5'd16)
            #10;
        #1;
        if (wb_valid && wb_id != 5'd16)
            $display("FAIL: consecutive id16 not seen (got id %0d)", wb_id);
        $display("  Cycle [%0d]: latency=2 cycles", 5'd16);
        check_result(32'h41400000, 5'd0, 5'd16);

        $display("============================================");
        $display("fma_unit tests finished: %0d passed, %0d errors", tests, errors);
        $display("  waveform: tb_fma_unit.vcd");
        $display("============================================");
        if (errors)
            $finish(1);
        else
            $finish(0);
    end

endmodule
