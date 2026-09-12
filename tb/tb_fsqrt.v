`include "fpu_config.vh"
`include "fpu_tb_util.vh"

//////////////////////////////////////////////////////////////////////////////
//
// tb_fsqrt - fsqrt 单元测试 (radix-4 SRT)
//   期望值由 /tmp/opencode/gen_srt_sqrt.py 的 make_vec() 生成(已验证双精度参考)。
//   覆盖: 完全平方 / 不精确 / 次正规 / 大指数 / 各种舍入 / 特殊值(±0,±inf,NaN,负数)
//
//////////////////////////////////////////////////////////////////////////////

module tb_fsqrt;
    localparam ID_WIDTH = 5;

    localparam [4:0] FL_NV = (1 << `NV);
    localparam [4:0] FL_NX = (1 << `NX);

    reg clk;
    reg rst;

    reg                 issue_valid;
    reg [ID_WIDTH-1:0]  issue_id;
    reg [2:0]           rm;
    reg [31:0]          src1;
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

    wire               s1_sign;
    wire signed [ 8:0] s1_exp ;
    wire        [23:0] s1_sig ;
    wire               s1_zero;
    wire               s1_inf ;
    wire               s1_nan ;
    wire               s1_snan;

    fpu_decoder u_dec1 (.a(src1), .sign(s1_sign), .exp(s1_exp), .sig(s1_sig),
                        .is_zero(s1_zero), .is_inf(s1_inf),
                        .is_nan(s1_nan), .is_snan(s1_snan));

    fsqrt #(.ID_WIDTH(ID_WIDTH)) u_dut (
        .clk        (clk),
        .rst        (rst),
        .issue_valid(issue_valid),
        .issue_id   (issue_id),
        .rm         (rm),
        .s1_sign    (s1_sign),
        .s1_exp     (s1_exp),
        .s1_sig     (s1_sig),
        .s1_zero    (s1_zero),
        .s1_inf     (s1_inf),
        .s1_nan     (s1_nan),
        .s1_snan    (s1_snan),
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
            if (!pass)
                $display("  Expected result=0x%08h fflags=0x%02h id=%0d",
                         exp_r, exp_f, exp_i);
            if (!pass)
                errors = errors + 1;
            tests  = tests + 1;
            exp_pending = 1'b0;
        end
    endtask

    task run_one;
        input [31:0] a;
        input [2:0]  rm_in;
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
            rm          = rm_in;
            src1        = a;
            flush       = 1'b0;
            flush_id    = 5'b0;

            exp_result  = exp_r;
            exp_fflags  = exp_f;
            exp_id      = id_in;
            exp_pending = 1'b1;
            issue_t     = $time;

            $display("Issue [%0d] FSQRT   %g           rm=%1d", id_in,
                     $bitstoreal(single_to_double(a)), rm_in);

            #10;
            issue_valid = 1'b0;

            while (!wb_valid) begin
                #10;
            end

            #1;
            latency = ($time - issue_t) / 10;
            $display("  Cycle [%0d]: latency=%0d cycles", id_in, latency);
            check_result(exp_result, exp_fflags, exp_id);
        end
    endtask

    task run_all_rm;
        input [31:0] a;
        input [31:0] e0;
        input [31:0] e1;
        input [31:0] e2;
        input [31:0] e3;
        input [31:0] e4;
        input [4:0]  f0;
        input [4:0]  f1;
        input [4:0]  f2;
        input [4:0]  f3;
        input [4:0]  f4;
        integer t;
        begin
            t = tests;
            run_one(a, `RNE, e0, f0, t[4:0]);
            run_one(a, `RTZ, e1, f1, t[4:0]);
            run_one(a, `RDN, e2, f2, t[4:0]);
            run_one(a, `RUP, e3, f3, t[4:0]);
            run_one(a, `RMM, e4, f4, t[4:0]);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        issue_valid = 1'b0;
        issue_id    = 5'b0;
        rm          = `RNE;
        src1        = 32'd0;
        flush       = 1'b0;
        flush_id    = 5'b0;
        errors      = 0;
        tests       = 0;
        exp_pending = 1'b0;

        $dumpfile("tb_fsqrt.vcd");
        $dumpvars(0, tb_fsqrt);

        #30 rst = 1'b0;
        #20;

        // 完全平方 (精确, 无 NX)
        run_all_rm(32'h3f800000, 32'h3f800000, 32'h3f800000, 32'h3f800000, 32'h3f800000, 32'h3f800000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 1.0
        run_all_rm(32'h40800000, 32'h40000000, 32'h40000000, 32'h40000000, 32'h40000000, 32'h40000000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 4.0
        run_all_rm(32'h41100000, 32'h40400000, 32'h40400000, 32'h40400000, 32'h40400000, 32'h40400000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 9.0
        run_all_rm(32'h3e800000, 32'h3f000000, 32'h3f000000, 32'h3f000000, 32'h3f000000, 32'h3f000000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 0.25
        run_all_rm(32'h42c80000, 32'h41200000, 32'h41200000, 32'h41200000, 32'h41200000, 32'h41200000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 100.0

        // 不精确: 各舍入模式
        run_all_rm(32'h40000000, 32'h3fb504f3, 32'h3fb504f3, 32'h3fb504f3, 32'h3fb504f4, 32'h3fb504f3,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 2.0
        run_all_rm(32'h40400000, 32'h3fddb3d7, 32'h3fddb3d7, 32'h3fddb3d7, 32'h3fddb3d8, 32'h3fddb3d7,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 3.0
        run_all_rm(32'h3f000000, 32'h3f3504f3, 32'h3f3504f3, 32'h3f3504f3, 32'h3f3504f4, 32'h3f3504f3,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 0.5
        run_all_rm(32'h40e00000, 32'h402953fd, 32'h402953fd, 32'h402953fd, 32'h402953fe, 32'h402953fd,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 7.0
        run_all_rm(32'h3e99999a, 32'h3f0c378c, 32'h3f0c378b, 32'h3f0c378b, 32'h3f0c378c, 32'h3f0c378c,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 0.3

        // 大指数 + 次正规
        run_all_rm(32'h7149f2ca, 32'h58635fa9, 32'h58635fa9, 32'h58635fa9, 32'h58635faa, 32'h58635fa9,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 1e30
        run_all_rm(32'h00800000, 32'h20000000, 32'h20000000, 32'h20000000, 32'h20000000, 32'h20000000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // 2.9387e-39
        run_all_rm(32'h00000001, 32'h1a3504f3, 32'h1a3504f3, 32'h1a3504f3, 32'h1a3504f4, 32'h1a3504f3,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 最小次正规
        run_all_rm(32'h00700000, 32'h1fef7751, 32'h1fef7750, 32'h1fef7750, 32'h1fef7751, 32'h1fef7751,
                   5'd1, 5'd1, 5'd1, 5'd1, 5'd1);                    // 次正规(奇指数路径)

        // 特殊值
        run_all_rm(32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // +0
        run_all_rm(32'h80000000, 32'h80000000, 32'h80000000, 32'h80000000, 32'h80000000, 32'h80000000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // -0
        run_all_rm(32'h7f800000, 32'h7f800000, 32'h7f800000, 32'h7f800000, 32'h7f800000, 32'h7f800000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // +inf
        run_all_rm(32'hc0800000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000,
                   5'd16, 5'd16, 5'd16, 5'd16, 5'd16);                   // -4.0 -> NaN+NV
        run_all_rm(32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000,
                   5'd0, 5'd0, 5'd0, 5'd0, 5'd0);                    // QNaN (quiet: 0 flags)
        run_all_rm(32'h7f800001, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000, 32'h7fc00000,
                   5'd16, 5'd16, 5'd16, 5'd16, 5'd16);               // SNaN -> NV

        $display("============================================");
        $display("fsqrt tests finished: %0d passed, %0d errors", tests, errors);
        $display("  waveform: tb_fsqrt.vcd");
        $display("============================================");
        if (errors)
            $finish(1);
        else
            $finish(0);
    end

endmodule