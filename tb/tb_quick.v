`include "fpu_config.vh"

// 临时回归: fquick 零与小数比较
module tb_quick;
    localparam ID_WIDTH = 5;

    reg clk, rst, valid, flush;
    reg [6:0]  fpu_op;
    reg [2:0]  rm;
    reg [31:0] src1, src2, src3;
    reg [ID_WIDTH-1:0] flush_id, fpu_id;
    wire ready, fpu_valid;
    wire [ID_WIDTH-1:0] fpu_id_o;
    wire [31:0] fpu_result;
    wire [4:0]  fpu_fflags;

    integer errors;
    integer tests;

    fpu #(.ID_WIDTH(ID_WIDTH)) u_dut (
        .clk(clk), .rst(rst), .valid(valid), .ready(ready),
        .fpu_op(fpu_op), .rm(rm), .src1(src1), .src2(src2), .src3(src3),
        .flush(flush), .flush_id(flush_id), .fpu_id(fpu_id),
        .fpu_valid(fpu_valid), .fpu_id_o(fpu_id_o),
        .fpu_result(fpu_result), .fpu_fflags(fpu_fflags));

    always #5 clk = ~clk;

    task name_issue;
        input [6:0] op_in;
        input [31:0] a;
        input [31:0] b;
        input [31:0] exp_r;
        reg [7:0] nm;
        begin
            case (op_in)
                `FLT_S : begin $write("flt  "); end
                `FLE_S : begin $write("fle  "); end
                `FEQ_S : begin $write("feq  "); end
                `FMIN_S: begin $write("fmin "); end
                `FMAX_S: begin $write("fmax "); end
                default: begin $write("op%d  ", op_in); end
            endcase
            @(negedge clk); #1;
            valid = 1'b1; fpu_op = op_in; rm = `RNE;
            src1 = a; src2 = b; src3 = 32'h00000000;
            fpu_id = 5'd0;
            #10;
            if (fpu_valid && (fpu_result === exp_r)) begin
                $display("[%0d] %08h,%08h -> %08h == %08h OK", tests, a, b, fpu_result, exp_r);
            end else begin
                $display("[%0d] %08h,%08h -> %08h != %08h FAIL", tests, a, b, fpu_result, exp_r);
                errors = errors + 1;
            end
            valid = 1'b0;
            tests = tests + 1;
        end
    endtask

    localparam POS0 = 32'h00000000;
    localparam NEG0 = 32'h80000000;
    localparam EPS  = 32'h358637bd; // ~1e-6
    localparam NEG2 = 32'hc0000000; // -2.0
    localparam NEG1 = 32'hbf800000; // -1.0
    localparam ONE  = 32'h3f800000; // +1.0

    initial begin
        clk = 1'b0; rst = 1'b1; valid = 1'b0; flush = 1'b0;
        fpu_op = 0; rm = `RNE; src1 = 0; src2 = 0; src3 = 0;
        fpu_id = 0; flush_id = 0; errors = 0; tests = 0;
        #5 rst = 1'b0;
        #10;

        // flt: a < b
        name_issue(`FLT_S, POS0, EPS , 32'd1);   // 0 < 1e-6: 1
        name_issue(`FLT_S, EPS , POS0, 32'd0);   // 1e-6 < 0: 0  (matrix bug)
        name_issue(`FLT_S, NEG0, POS0, 32'd0);   // -0 < +0: 0 (IEEE)
        name_issue(`FLT_S, NEG0, EPS , 32'd1);   // -0 < 1e-6: 1
        name_issue(`FLT_S, EPS , NEG0, 32'd0);   // 1e-6 < -0: 0
        name_issue(`FLT_S, NEG2, EPS , 32'd1);   // -2 < 1e-6: 1
        name_issue(`FLT_S, EPS , NEG1, 32'd0);   // 1e-6 < -1: 0
        name_issue(`FLT_S, POS0, POS0, 32'd0);   // 0 < 0: 0
        name_issue(`FLT_S, ONE , EPS , 32'd0);   // 1 < 1e-6: 0
        name_issue(`FLT_S, EPS , ONE , 32'd1);   // 1e-6 < 1: 1
        name_issue(`FLT_S, NEG2, NEG1, 32'd1);   // -2 < -1: 1

        // fle: a <= b
        name_issue(`FLE_S, POS0, NEG0, 32'd1);   // 0 <= -0: 1
        name_issue(`FLE_S, EPS , POS0, 32'd0);   // 1e-6 <= 0: 0
        name_issue(`FLE_S, POS0, EPS , 32'd1);   // 0 <= 1e-6: 1

        // feq
        name_issue(`FEQ_S, NEG0, POS0, 32'd1);   // -0 == +0: 1
        name_issue(`FEQ_S, POS0, EPS , 32'd0);   // 0 == 1e-6: 0

        // fmin/fmax with zero + tiny
        name_issue(`FMIN_S, POS0, EPS, POS0);    // min(0,1e-6)=+0
        name_issue(`FMIN_S, EPS , POS0, POS0);   // min(1e-6,0)=+0
        name_issue(`FMAX_S, POS0, EPS, EPS);     // max(0,1e-6)=1e-6
        name_issue(`FMAX_S, EPS , POS0, EPS);    // max(1e-6,0)=1e-6
        name_issue(`FMIN_S, NEG0, POS0, NEG0);   // min(-0,+0)=-0
        name_issue(`FMAX_S, NEG0, POS0, POS0);   // max(-0,+0)=+0
        name_issue(`FMIN_S, NEG0, EPS , NEG0);   // min(-0,1e-6)=-0
        name_issue(`FMAX_S, NEG0, EPS , EPS);    // max(-0,1e-6)=1e-6

        $display("========================================");
        $display("quick tests: %0d passed, %0d errors", tests - errors, errors);
        $display("========================================");
        $finish(errors ? 1 : 0);
    end
endmodule