`timescale 1ns/1ps

module tb_fp_only;
    reg clk;
    reg reset;
    integer fails;
    integer i;

    // FP opcodes
    localparam OP_ADDF = 5'h14;
    localparam OP_SUBF = 5'h15;
    localparam OP_MULF = 5'h16;
    localparam OP_DIVF = 5'h17;

    tinker_core uut (
        .clk(clk),
        .reset(reset)
    );

    // clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ----------------------------
    // Instruction encoder
    // [31:27] opcode
    // [26:22] rd
    // [21:17] rs
    // [16:12] rt
    // [11:0]  literal
    // ----------------------------
    function [31:0] enc_rrr;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        begin
            enc_rrr = {opcode, rd, rs, rt, 12'd0};
        end
    endfunction

    // ----------------------------
    // Helpers
    // ----------------------------
    task write_inst;
        input [63:0] addr;
        input [31:0] inst;
        begin
            uut.memory.bytes[addr+0] = inst[7:0];
            uut.memory.bytes[addr+1] = inst[15:8];
            uut.memory.bytes[addr+2] = inst[23:16];
            uut.memory.bytes[addr+3] = inst[31:24];
        end
    endtask

    task clear_prog_region;
        begin
            for (i = 16'h2000; i < 16'h2040; i = i + 1)
                uut.memory.bytes[i] = 8'h00;
        end
    endtask

    task do_reset;
        begin
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            reset = 1'b0;
            #1;
        end
    endtask

    task expect64;
        input [255:0] label;
        input [63:0] got;
        input [63:0] expected;
        begin
            if (got !== expected) begin
                fails = fails + 1;
                $display("FAIL %-20s got=%h expected=%h", label, got, expected);
            end else begin
                $display("PASS %-20s %h", label, got);
            end
        end
    endtask

    task expect_nan;
        input [255:0] label;
        input [63:0] got;
        begin
            if ((got[62:52] == 11'h7ff) && (got[51:0] != 0)) begin
                $display("PASS %-20s %h", label, got);
            end else begin
                fails = fails + 1;
                $display("FAIL %-20s got=%h expected=NaN", label, got);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/fp_only.vcd");
        $dumpvars(0, tb_fp_only);

        fails = 0;
        reset = 1'b0;

        // --------------------------------
        // TEST 1: ADDF 1.5 + 1.5 = 3.0
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd1, 5'd2, 5'd3));
        do_reset();

        uut.reg_file.registers[2] = 64'h3FF8_0000_0000_0000; // 1.5
        uut.reg_file.registers[3] = 64'h3FF8_0000_0000_0000; // 1.5

        @(posedge clk); #1;
        expect64("ADDF basic", uut.reg_file.registers[1], 64'h4008_0000_0000_0000); // 3.0

        // --------------------------------
        // TEST 2: SUBF 5.5 - 2.25 = 3.25
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_SUBF, 5'd4, 5'd5, 5'd6));
        do_reset();

        uut.reg_file.registers[5] = 64'h4016_0000_0000_0000; // 5.5
        uut.reg_file.registers[6] = 64'h4002_0000_0000_0000; // 2.25

        @(posedge clk); #1;
        expect64("SUBF basic", uut.reg_file.registers[4], 64'h400A_0000_0000_0000); // 3.25

        // --------------------------------
        // TEST 3: MULF 2.5 * 4.0 = 10.0
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_MULF, 5'd7, 5'd8, 5'd9));
        do_reset();

        uut.reg_file.registers[8] = 64'h4004_0000_0000_0000; // 2.5
        uut.reg_file.registers[9] = 64'h4010_0000_0000_0000; // 4.0

        @(posedge clk); #1;
        expect64("MULF basic", uut.reg_file.registers[7], 64'h4024_0000_0000_0000); // 10.0

        // --------------------------------
        // TEST 4: DIVF 7.5 / 2.5 = 3.0
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_DIVF, 5'd10, 5'd11, 5'd12));
        do_reset();

        uut.reg_file.registers[11] = 64'h401E_0000_0000_0000; // 7.5
        uut.reg_file.registers[12] = 64'h4004_0000_0000_0000; // 2.5

        @(posedge clk); #1;
        expect64("DIVF basic", uut.reg_file.registers[10], 64'h4008_0000_0000_0000); // 3.0

        // --------------------------------
        // TEST 5: +inf + 1.0 = +inf
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd13, 5'd14, 5'd15));
        do_reset();

        uut.reg_file.registers[14] = 64'h7FF0_0000_0000_0000; // +inf
        uut.reg_file.registers[15] = 64'h3FF0_0000_0000_0000; // 1.0

        @(posedge clk); #1;
        expect64("ADDF inf", uut.reg_file.registers[13], 64'h7FF0_0000_0000_0000);

        // --------------------------------
        // TEST 6: 0.0 / 5.0 = 0.0
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_DIVF, 5'd16, 5'd17, 5'd18));
        do_reset();

        uut.reg_file.registers[17] = 64'h0000_0000_0000_0000; // 0.0
        uut.reg_file.registers[18] = 64'h4014_0000_0000_0000; // 5.0

        @(posedge clk); #1;
        expect64("DIVF zero", uut.reg_file.registers[16], 64'h0000_0000_0000_0000);

        // --------------------------------
        // TEST 7: 1.0 / 0.0 = +inf
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_DIVF, 5'd19, 5'd20, 5'd21));
        do_reset();

        uut.reg_file.registers[20] = 64'h3FF0_0000_0000_0000; // 1.0
        uut.reg_file.registers[21] = 64'h0000_0000_0000_0000; // 0.0

        @(posedge clk); #1;
        expect64("DIVF by zero", uut.reg_file.registers[19], 64'h7FF0_0000_0000_0000);

        // --------------------------------
        // TEST 8: NaN + 1.0 = NaN
        // --------------------------------
        clear_prog_region();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd22, 5'd23, 5'd24));
        do_reset();

        uut.reg_file.registers[23] = 64'h7FF8_0000_0000_0001; // NaN
        uut.reg_file.registers[24] = 64'h3FF0_0000_0000_0000; // 1.0

        @(posedge clk); #1;
        expect_nan("ADDF NaN", uut.reg_file.registers[22]);

        if (fails == 0)
            $display("\nALL FP TESTS PASSED");
        else
            $display("\nFP TESTS FAILED: %0d", fails);

        $finish;
    end
endmodule