`timescale 1ns/1ps

module tb_branch_only;
    reg clk;
    reg reset;
    integer fails;
    integer i;

    localparam MEM_SIZE = 512 * 1024;
    localparam SP_INIT  = MEM_SIZE;
    localparam RET_SLOT = MEM_SIZE - 8;

    // Branch/control opcodes
    localparam OP_BR        = 5'h08;
    localparam OP_BRR_REG   = 5'h09;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_CALL      = 5'h0c;
    localparam OP_RETURN    = 5'h0d;
    localparam OP_BRGT      = 5'h0e;

    tinker_core uut (
        .clk(clk),
        .reset(reset)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ----------------------------
    // Instruction encoders
    // Format:
    // [31:27] opcode
    // [26:22] rd
    // [21:17] rs
    // [16:12] rt
    // [11:0]  literal
    // ----------------------------
    function [31:0] enc_r;
        input [4:0] opcode;
        input [4:0] rd;
        begin
            enc_r = {opcode, rd, 5'd0, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_rr;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        begin
            enc_rr = {opcode, rd, rs, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_rrr;
        input [4:0] opcode;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        begin
            enc_rrr = {opcode, rd, rs, rt, 12'd0};
        end
    endfunction

    function [31:0] enc_lit;
        input [4:0] opcode;
        input [11:0] lit;
        begin
            enc_lit = {opcode, 5'd0, 5'd0, 5'd0, lit};
        end
    endfunction

    // ----------------------------
    // Memory helpers
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

    task write_mem64;
        input [63:0] addr;
        input [63:0] data;
        begin
            uut.memory.bytes[addr+0] = data[7:0];
            uut.memory.bytes[addr+1] = data[15:8];
            uut.memory.bytes[addr+2] = data[23:16];
            uut.memory.bytes[addr+3] = data[31:24];
            uut.memory.bytes[addr+4] = data[39:32];
            uut.memory.bytes[addr+5] = data[47:40];
            uut.memory.bytes[addr+6] = data[55:48];
            uut.memory.bytes[addr+7] = data[63:56];
        end
    endtask

    task clear_prog_region;
        begin
            for (i = 16'h2000; i < 16'h2080; i = i + 1)
                uut.memory.bytes[i] = 8'h00;
        end
    endtask

    task clear_ret_slot;
        begin
            write_mem64(RET_SLOT, 64'd0);
        end
    endtask

    // ----------------------------
    // Reset helper
    // ----------------------------
    task do_reset;
        begin
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            reset = 1'b0;
            #1;
        end
    endtask

    // ----------------------------
    // Check helpers
    // ----------------------------
    task expect_pc;
        input [255:0] label;
        input [63:0] expected;
        begin
            if (uut.fetch.pc !== expected) begin
                fails = fails + 1;
                $display("FAIL %-20s pc=%h expected=%h", label, uut.fetch.pc, expected);
            end else begin
                $display("PASS %-20s pc=%h", label, uut.fetch.pc);
            end
        end
    endtask

    task expect_mem64;
        input [255:0] label;
        input [63:0] addr;
        input [63:0] expected;
        reg [63:0] got;
        begin
            got = {
                uut.memory.bytes[addr+7],
                uut.memory.bytes[addr+6],
                uut.memory.bytes[addr+5],
                uut.memory.bytes[addr+4],
                uut.memory.bytes[addr+3],
                uut.memory.bytes[addr+2],
                uut.memory.bytes[addr+1],
                uut.memory.bytes[addr+0]
            };
            if (got !== expected) begin
                fails = fails + 1;
                $display("FAIL %-20s mem[%h]=%h expected=%h", label, addr, got, expected);
            end else begin
                $display("PASS %-20s mem[%h]=%h", label, addr, got);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/branch_only.vcd");
        $dumpvars(0, tb_branch_only);

        fails = 0;
        reset = 1'b0;

        // ----------------------------
        // TEST 1: BR rd
        // pc <- rd
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_r(OP_BR, 5'd20));
        do_reset();

        uut.reg_file.registers[20] = 64'h0000_0000_0000_2040;

        @(posedge clk); #1;
        expect_pc("BR rd", 64'h0000_0000_0000_2040);

        // ----------------------------
        // TEST 2: BRR rd
        // pc <- pc + rd
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_r(OP_BRR_REG, 5'd21));
        do_reset();

        uut.reg_file.registers[21] = 64'd8;

        @(posedge clk); #1;
        expect_pc("BRR rd", 64'h0000_0000_0000_2008);

        // ----------------------------
        // TEST 3: BRR literal
        // pc <- pc + L
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_lit(OP_BRR_LIT, 12'd12));
        do_reset();

        @(posedge clk); #1;
        expect_pc("BRR literal", 64'h0000_0000_0000_200C);

        // ----------------------------
        // TEST 4: BRNZ taken
        // if rs != 0, pc <- rd
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd5, 5'd6));
        do_reset();

        uut.reg_file.registers[5] = 64'h0000_0000_0000_2030; // target
        uut.reg_file.registers[6] = 64'd1;                   // condition != 0

        @(posedge clk); #1;
        expect_pc("BRNZ taken", 64'h0000_0000_0000_2030);

        // ----------------------------
        // TEST 5: BRNZ not taken
        // if rs == 0, fall through
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd5, 5'd6));
        do_reset();

        uut.reg_file.registers[5] = 64'h0000_0000_0000_2030;
        uut.reg_file.registers[6] = 64'd0;

        @(posedge clk); #1;
        expect_pc("BRNZ not taken", 64'h0000_0000_0000_2004);

        // ----------------------------
        // TEST 6: CALL
        // Mem[r31-8] <- pc+4; pc <- rd
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_r(OP_CALL, 5'd10));
        do_reset();

        uut.reg_file.registers[10] = 64'h0000_0000_0000_2050;

        @(posedge clk); #1;
        expect_pc("CALL jump", 64'h0000_0000_0000_2050);
        expect_mem64("CALL saved PC", RET_SLOT, 64'h0000_0000_0000_2004);

        // ----------------------------
        // TEST 7: RETURN
        // pc <- Mem[r31-8]
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_r(OP_RETURN, 5'd0));
        write_mem64(RET_SLOT, 64'h0000_0000_0000_2060);
        do_reset();

        @(posedge clk); #1;
        expect_pc("RETURN", 64'h0000_0000_0000_2060);

        // ----------------------------
        // TEST 8: BRGT taken
        // if signed(rs) > signed(rt), pc <- rd
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_rrr(OP_BRGT, 5'd7, 5'd8, 5'd9));
        do_reset();

        uut.reg_file.registers[7] = 64'h0000_0000_0000_2070; // target
        uut.reg_file.registers[8] = 64'd9;
        uut.reg_file.registers[9] = 64'd3;

        @(posedge clk); #1;
        expect_pc("BRGT taken", 64'h0000_0000_0000_2070);

        // ----------------------------
        // TEST 9: BRGT signed not taken
        // -1 > 1 is false (signed compare)
        // ----------------------------
        clear_prog_region();
        clear_ret_slot();
        write_inst(64'h2000, enc_rrr(OP_BRGT, 5'd7, 5'd8, 5'd9));
        do_reset();

        uut.reg_file.registers[7] = 64'h0000_0000_0000_2070;
        uut.reg_file.registers[8] = 64'hFFFF_FFFF_FFFF_FFFF; // -1
        uut.reg_file.registers[9] = 64'd1;

        @(posedge clk); #1;
        expect_pc("BRGT signed no", 64'h0000_0000_0000_2004);

        if (fails == 0)
            $display("\nALL BRANCH TESTS PASSED");
        else
            $display("\nBRANCH TESTS FAILED: %0d", fails);

        $finish;
    end
endmodule