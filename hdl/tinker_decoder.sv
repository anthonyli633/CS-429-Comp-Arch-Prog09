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
    assign opcode   = instruction[31:27];
    assign rd_idx   = instruction[26:22];
    assign rs_idx   = instruction[21:17];
    assign rt_idx   = instruction[16:12];
    assign lit12    = instruction[11:0];
    assign lit_zext = {52'd0, instruction[11:0]};
    assign lit_sext = {{52{instruction[11]}}, instruction[11:0]};
endmodule