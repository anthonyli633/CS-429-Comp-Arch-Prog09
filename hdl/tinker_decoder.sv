`timescale 1ns/1ps

module tinker_decoder(
    input  [31:0] instruction,
    output [4:0]  opcode,
    output [4:0]  rd_idx,
    output [4:0]  rs_idx,
    output [4:0]  rt_idx,
    output [11:0] lit12,
    output [63:0] lit_zext,
    output [63:0] lit_sext
);
    assign opcode   = instruction[4:0];
    assign rd_idx   = instruction[9:5];
    assign rs_idx   = instruction[14:10];
    assign rt_idx   = instruction[19:15];
    assign lit12    = instruction[31:20];
    assign lit_zext = {52'd0, instruction[31:20]};
    assign lit_sext = {{52{instruction[31]}}, instruction[31:20]};
endmodule
