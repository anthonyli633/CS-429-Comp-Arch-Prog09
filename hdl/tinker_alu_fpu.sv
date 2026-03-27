`timescale 1ns/1ps

module tinker_alu_fpu(
    input  [63:0] a,
    input  [63:0] b,
    input  [5:0]  op,
    output reg [63:0] result,
    output wire a_is_zero,
    output wire a_gt_b_signed
);
    localparam ALU_PASS_A = 6'd0;
    localparam ALU_PASS_B = 6'd1;
    localparam ALU_AND    = 6'd2;
    localparam ALU_OR     = 6'd3;
    localparam ALU_XOR    = 6'd4;
    localparam ALU_NOT    = 6'd5;
    localparam ALU_SHR    = 6'd6;
    localparam ALU_SHL    = 6'd7;
    localparam ALU_ADD    = 6'd8;
    localparam ALU_SUB    = 6'd9;
    localparam ALU_MUL    = 6'd10;
    localparam ALU_DIV    = 6'd11;
    localparam ALU_FADD   = 6'd12;
    localparam ALU_FSUB   = 6'd13;
    localparam ALU_FMUL   = 6'd14;
    localparam ALU_FDIV   = 6'd15;

    localparam QUIET_NAN  = 64'h7ff8_0000_0000_0000;

    assign a_is_zero      = (a == 64'd0);
    assign a_gt_b_signed  = ($signed(a) > $signed(b));

    always @(*) begin
        case (op)
            ALU_PASS_A: result = a;
            ALU_PASS_B: result = b;
            ALU_AND   : result = a & b;
            ALU_OR    : result = a | b;
            ALU_XOR   : result = a ^ b;
            ALU_NOT   : result = ~a;
            ALU_SHR   : result = a >> b[5:0];
            ALU_SHL   : result = a << b[5:0];
            ALU_ADD   : result = $signed(a) + $signed(b);
            ALU_SUB   : result = $signed(a) - $signed(b);
            ALU_MUL   : result = $signed(a) * $signed(b);
            ALU_DIV   : result = (b == 64'd0) ? 64'd0 : $signed(a) / $signed(b);
            // TODO
            ALU_FADD  : result = QUIET_NAN;
            ALU_FSUB  : result = QUIET_NAN;
            ALU_FMUL  : result = QUIET_NAN;
            ALU_FDIV  : result = QUIET_NAN;
            default   : result = 64'd0;
        endcase
    end
endmodule
