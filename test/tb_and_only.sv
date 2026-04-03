`timescale 1ns/1ps

module tb_and_only;
    reg clk = 1'b0;
    reg reset = 1'b1;

    tinker_core dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    function [31:0] enc_rrr;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        begin
            enc_rrr = {12'd0, rt, rs, rd, opcode};
        end
    endfunction

    task put32_le;
        input [63:0] addr;
        input [31:0] word;
        begin
            dut.memory.bytes[addr + 0] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    localparam OP_AND = 5'h01;

    reg [31:0] instr;

    initial begin
        instr = enc_rrr(OP_AND, 5'd1, 5'd2, 5'd3);
        put32_le(64'h0000_0000_0000_2000, instr);

        // Reset cycle
        @(posedge clk);
        #1;
        reset = 1'b0;

        // Set source registers AFTER reset so reset doesn't wipe them
        dut.reg_file.registers[2] = 64'hF0F0_F0F0_F0F0_F0F0;
        dut.reg_file.registers[3] = 64'h0FF0_0FF0_0FF0_0FF0;

        // Let one instruction execute
        @(posedge clk);
        #1;

        $display("loaded instr = %h", instr);
        $display("fetched instr = %h", dut.instruction);
        $display("r1 = %h", dut.reg_file.registers[1]);
        $display("r2 = %h", dut.reg_file.registers[2]);
        $display("r3 = %h", dut.reg_file.registers[3]);

        if (dut.reg_file.registers[1] === 64'hFFF0_FFF0_FFF0_FFF0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end
endmodule