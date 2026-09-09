`include "fpu_config.vh"
`include "fpu_tb_util.vh"

module tb_fpu;
    localparam ID_WIDTH = 5;

    // fflags 位序与 rtl/fpu_config.vh 保持一致: NV=4 DZ=3 OF=2 UF=1 NX=0
    localparam [4:0] FL_NV = (1 << `NV);
    localparam [4:0] FL_DZ = (1 << `DZ);
    localparam [4:0] FL_OF = (1 << `OF);
    localparam [4:0] FL_UF = (1 << `UF);
    localparam [4:0] FL_NX = (1 << `NX);

    reg clk;
    reg rst;
    reg  valid;
    reg  [6:0] fpu_op;
    reg  [2:0] rm;
    reg  [31:0] src1;
    reg  [31:0] src2;
    reg  [31:0] src3;
    reg  flush;
    reg  [ID_WIDTH-1:0] flush_id;
    reg  [ID_WIDTH-1:0] fpu_id;

    wire ready;
    wire fpu_valid;
    wire [ID_WIDTH-1:0] fpu_id_o;
    wire [31:0] fpu_result;
    wire [4:0]  fpu_fflags;

    integer errors;
    integer tests;

    fpu #(.ID_WIDTH(ID_WIDTH)) u_dut (
        .clk        (clk),
        .rst        (rst),
        .valid      (valid),
        .ready      (ready),
        .fpu_op     (fpu_op),
        .rm         (rm),
        .src1       (src1),
        .src2       (src2),
        .src3       (src3),
        .flush      (flush),
        .flush_id   (flush_id),
        .fpu_id     (fpu_id),
        .fpu_valid  (fpu_valid),
        .fpu_id_o   (fpu_id_o),
        .fpu_result (fpu_result),
        .fpu_fflags (fpu_fflags)
    );

    always #5 clk = ~clk;

    task print_issue;
        input [6:0] op_in;
        input [31:0] a;
        input [31:0] b;
        input [31:0] c;
        begin
            $display("");
            case (op_in)
                `FADD_S:   $display("FADD    %g + %g",
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)));
                `FSUB_S:   $display("FSUB    %g - %g", 
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)));
                `FMUL_S:   $display("FMUL    %g * %g",
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)));
                `FMADD_S:  $display("FMADD   %g * %g + %g",
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)));
                `FMSUB_S:  $display("FMSUB   %g * %g - %g",
                                    $bitstoreal(single_to_double(a)),
                                    $bitstoreal(single_to_double(b)),
                                    $bitstoreal(single_to_double(c)));
                default:   $display("op=%0d", op_in);
            endcase
        end
    endtask

    task check;
        input [31:0] exp_r;
        input [4:0]  exp_f;
        input [ID_WIDTH-1:0] exp_id;
        reg pass;
        begin
            pass = fpu_valid && (fpu_result === exp_r) &&
                   (fpu_fflags === exp_f) && (fpu_id_o === exp_id);
            if (fpu_valid) begin
                $display("  Retire [%0d] result = 0x%08h fflags = 0x%02h    %s",
                         fpu_id_o, fpu_result, fpu_fflags, pass ? "PASS" : "FAIL");
            end else begin
                $display("  Retire [%0d] fpu_valid = 0    FAIL", exp_id);
            end
            if (!pass) begin
                $display("  Expected result = 0x%08h fflags = 0x%02h id = %0d",
                         exp_r, exp_f, exp_id);
                errors = errors + 1;
            end
            tests = tests + 1;
        end
    endtask

    task run_top;
        input [6:0] op_in;
        input [31:0] a;
        input [31:0] b;
        input [31:0] c;
        input [31:0] exp_r;
        input [4:0]  exp_f;
        input [ID_WIDTH-1:0] id_in;
        integer issue_t;
        integer latency;
        begin
            @(negedge clk);
            #1;
            valid   = 1'b1;
            fpu_op  = op_in;
            rm      = `RNE;
            src1    = a;
            src2    = b;
            src3    = c;
            flush   = 1'b0;
            flush_id= 5'b0;
            fpu_id  = id_in;
            issue_t = $time;

            print_issue(op_in, a, b, c);

            #10;
            valid   = 1'b0;
            while (!fpu_valid) #10;
            #1;
            latency = ($time - issue_t) / 10;
            $display("  Cycle [%0d]: cycles = %0d",
                     id_in, latency);
            check(exp_r, exp_f, id_in);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        valid = 1'b0;
        fpu_op = 0;
        rm = `RNE;
        src1 = 0; src2 = 0; src3 = 0;
        flush = 1'b0;
        flush_id = 0;
        fpu_id = 0;
        errors = 0;
        tests = 0;

        $dumpfile("tb_fpu.vcd");
        $dumpvars(0, tb_fpu);

        #5 rst = 1'b0;
        #10;

        run_top(`FADD_S, 32'h3f800000, 32'h40000000, 32'h00000000,
                32'h40400000, 5'd0, 5'd0);
        run_top(`FMUL_S, 32'h40000000, 32'h40400000, 32'h00000000,
                32'h40c00000, 5'd0, 5'd1);
        run_top(`FMADD_S, 32'h40000000, 32'h40400000, 32'h40800000,
                32'h41200000, 5'd0, 5'd2);
        run_top(`FMUL_S, 32'h00000000, 32'h7f800000, 32'h00000000,
                32'h7fc00000, FL_NV, 5'd3);

        $display("============================================");
        $display("fpu top tests finished: %0d passed, %0d errors", tests, errors);
        $display("  waveform: tb_fpu.vcd");
        $display("============================================");
        if (errors)
            $finish(1);
        else
            $finish(0);
    end

endmodule
