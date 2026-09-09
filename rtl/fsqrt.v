`include "fpu_config.vh"

module fsqrt #(
    parameter ID_WIDTH = 5
)(
    input  wire                clk        ,
    input  wire                rst        ,

    input  wire                issue_valid,
    input  wire [ID_WIDTH-1:0] issue_id   ,
    input  wire [         2:0] rm         ,

    input  wire               s1_sign     , 
    input  wire signed [ 8:0] s1_exp      , 
    input  wire        [23:0] s1_sig      , 
    input  wire               s1_zero     , 
    input  wire               s1_inf      , 
    input  wire               s1_nan      , 
    input  wire               s1_snan     , 

    input  wire                flush      ,
    input  wire [ID_WIDTH-1:0] flush_id   ,

    output wire                wb_valid   ,
    output wire [ID_WIDTH-1:0] wb_id      ,
    output wire [        31:0] wb_result  ,
    output wire [         4:0] wb_fflags
);
endmodule
