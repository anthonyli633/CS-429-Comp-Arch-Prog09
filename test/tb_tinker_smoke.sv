`timescale 1ns/1ps

module tb_debug_tinker;
    reg clk;
    reg reset;
    integer fails;

    tinker_core dut (
        .clk(clk),
        .reset(reset)
    );

    // -----------------------------
    // Clock
    // -----------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // -----------------------------
    // Helpers: encode instructions
    // Format assumed by your core:
    // [31:20] L
    // [19:15] rt
    // [14:10] rs
    // [9:5]   rd
    // [4:0]   opcode
    // -----------------------------
    function [31:0] enc_rrr;
        input [4:0] op;
        input [4:0] rd;
        input [4:0] rs;
        input [4:0] rt;
        begin
            enc_rrr = {12'd0, rt, rs, rd, op};
        end
    endfunction

    function [31:0] enc_rd_lit;
        input [4:0] op;
        input [4:0] rd;
        input [11:0] lit;
        begin
            enc_rd_lit = {lit, 5'd0, 5'd0, rd, op};
        end
    endfunction

    function [31:0] enc_brnz;
        input [4:0] op;
        input [4:0] rd;
        input [4:0] rs;
        begin
            enc_brnz = {12'd0, 5'd0, rs, rd, op};
        end
    endfunction

    function [31:0] enc_mov_reg;
        input [4:0] op;
        input [4:0] rd;
        input [4:0] rs;
        begin
            enc_mov_reg = {12'd0, 5'd0, rs, rd, op};
        end
    endfunction

    // -----------------------------
    // Write one 32-bit instruction into memory at addr
    // Little-endian layout to match your memory module
    // -----------------------------
    task load_instr;
        input [63:0] addr;
        input [31:0] instr;
        begin
            dut.memory.bytes[addr + 64'd0] = instr[7:0];
            dut.memory.bytes[addr + 64'd1] = instr[15:8];
            dut.memory.bytes[addr + 64'd2] = instr[23:16];
            dut.memory.bytes[addr + 64'd3] = instr[31:24];
        end
    endtask

    task clear_prog_region;
        integer i;
        begin
            for (i = 16'h2000; i < 16'h2040; i = i + 1)
                dut.memory.bytes[i] = 8'h00;
        end
    endtask

    task set_reg;
        input [4:0] idx;
        input [63:0] val;
        begin
            dut.reg_file.registers[idx] = val;
        end
    endtask

    task reset_core;
        begin
            reset = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            reset = 1'b0;
            #1;
        end
    endtask

    task step_and_show;
        begin
            @(posedge clk);
            #1;
            show_state;
        end
    endtask

    task show_state;
        begin
            $display("------------------------------------------------------------");
            $display("t=%0t", $time);
            $display("PC          = %h", dut.fetch.pc);
            $display("instruction = %h", dut.instruction);
            $display("opcode=%0d rd=%0d rs=%0d rt=%0d lit=%h",
                     dut.opcode, dut.rd_idx, dut.rs_idx, dut.rt_idx, dut.lit12);
            $display("rd_data=%h rs_data=%h rt_data=%h sp=%h",
                     dut.rd_data, dut.rs_data, dut.rt_data, dut.sp_data);
            $display("alu_op=%0d alu_a=%h alu_b=%h alu_result=%h",
                     dut.alu_op, dut.alu_a, dut.alu_b, dut.alu_result);
            $display("rf_write_en=%b rf_write_addr=%0d rf_write_data=%h",
                     dut.rf_write_en, dut.rf_write_addr, dut.rf_write_data);
            $display("pc_redirect=%b pc_redirect_target=%h",
                     dut.pc_redirect, dut.pc_redirect_target);
            $display("data_write_en=%b data_addr=%h data_write_data=%h data_read_data=%h",
                     dut.data_write_en, dut.data_addr, dut.data_write_data, dut.data_read_data);
        end
    endtask

    task expect64;
        input [255:0] label;
        input [63:0] got;
        input [63:0] exp;
        begin
            if (got !== exp) begin
                fails = fails + 1;
                $display("FAIL: %0s got=%h expected=%h", label, got, exp);
            end else begin
                $display("PASS: %0s = %h", label, got);
            end
        end
    endtask

    task expect32;
        input [255:0] label;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                fails = fails + 1;
                $display("FAIL: %0s got=%h expected=%h", label, got, exp);
            end else begin
                $display("PASS: %0s = %h", label, got);
            end
        end
    endtask

    // -----------------------------
    // Opcodes from your current core
    // -----------------------------
    localparam OP_AND      = 5'h00;
    localparam OP_OR       = 5'h01;
    localparam OP_XOR      = 5'h02;
    localparam OP_NOT      = 5'h03;
    localparam OP_SHFTR    = 5'h04;
    localparam OP_SHFTRI   = 5'h05;
    localparam OP_SHFTL    = 5'h06;
    localparam OP_SHFTLI   = 5'h07;
    localparam OP_BR       = 5'h08;
    localparam OP_BRR_REG  = 5'h09;
    localparam OP_BRR_LIT  = 5'h0a;
    localparam OP_BRNZ     = 5'h0b;
    localparam OP_CALL     = 5'h0c;
    localparam OP_RETURN   = 5'h0d;
    localparam OP_BRGT     = 5'h0e;
    localparam OP_MOV_LOAD = 5'h10;
    localparam OP_MOV_REG  = 5'h11;
    localparam OP_MOV_LIT  = 5'h12;
    localparam OP_MOV_STORE= 5'h13;
    localparam OP_ADD      = 5'h18;
    localparam OP_ADDI     = 5'h19;
    localparam OP_SUB      = 5'h1a;
    localparam OP_SUBI     = 5'h1b;
    localparam OP_MUL      = 5'h1c;
    localparam OP_DIV      = 5'h1d;

    reg [31:0] instr;

    initial begin
        $dumpfile("vvp/tinker_debug.vcd");
        $dumpvars(0, tb_debug_tinker);

        fails = 0;
        reset = 1'b0;

        // =========================================================
        // 0) RESET CHECK
        // =========================================================
        reset_core;
        show_state;
        expect64("PC after reset", dut.fetch.pc, 64'h0000_0000_0000_2000);
        expect64("r31 after reset", dut.reg_file.registers[31], 64'd524288);
        expect64("r0 after reset", dut.reg_file.registers[0], 64'd0);

        // =========================================================
        // 1) AND r1, r2, r3
        // =========================================================
        clear_prog_region;
        instr = enc_rrr(OP_AND, 5'd1, 5'd2, 5'd3);
        load_instr(64'h2000, instr);
        set_reg(5'd2, 64'hF0F0_F0F0_F0F0_F0F0);
        set_reg(5'd3, 64'h0FF0_0FF0_0FF0_0FF0);

        #1;
        $display("\nTEST 1: AND r1, r2, r3");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);
        expect64("pre-step PC", dut.fetch.pc, 64'h2000);

        step_and_show;
        expect64("r1 after AND", dut.reg_file.registers[1],
                 64'h0000_FFF0_FFF0_FFF0);
        expect64("PC after AND", dut.fetch.pc, 64'h2004);

        // =========================================================
        // 2) OR r4, r5, r6
        // =========================================================
        reset_core;
        clear_prog_region;
        instr = enc_rrr(OP_OR, 5'd4, 5'd5, 5'd6);
        load_instr(64'h2000, instr);
        set_reg(5'd5, 64'hF000_0000_0000_000F);
        set_reg(5'd6, 64'h0F00_0000_0000_00F0);

        #1;
        $display("\nTEST 2: OR r4, r5, r6");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);

        step_and_show;
        expect64("r4 after OR", dut.reg_file.registers[4],
                 64'hFF00_0000_0000_00FF);
        expect64("PC after OR", dut.fetch.pc, 64'h2004);

        // =========================================================
        // 3) ADD r7, r8, r9
        // =========================================================
        reset_core;
        clear_prog_region;
        instr = enc_rrr(OP_ADD, 5'd7, 5'd8, 5'd9);
        load_instr(64'h2000, instr);
        set_reg(5'd8, 64'd10);
        set_reg(5'd9, 64'd32);

        #1;
        $display("\nTEST 3: ADD r7, r8, r9");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);

        step_and_show;
        expect64("r7 after ADD", dut.reg_file.registers[7], 64'd42);
        expect64("PC after ADD", dut.fetch.pc, 64'h2004);

        // =========================================================
        // 4) ADDI r10, 3   (rd <- rd + 3 in your design)
        // =========================================================
        reset_core;
        clear_prog_region;
        instr = enc_rd_lit(OP_ADDI, 5'd10, 12'd3);
        load_instr(64'h2000, instr);
        set_reg(5'd10, 64'd100);

        #1;
        $display("\nTEST 4: ADDI r10, 3");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);

        step_and_show;
        expect64("r10 after ADDI", dut.reg_file.registers[10], 64'd103);
        expect64("PC after ADDI", dut.fetch.pc, 64'h2004);

        // =========================================================
        // 5) MOV r11, r12
        // =========================================================
        reset_core;
        clear_prog_region;
        instr = enc_mov_reg(OP_MOV_REG, 5'd11, 5'd12);
        load_instr(64'h2000, instr);
        set_reg(5'd12, 64'h1234_5678_9ABC_DEF0);

        #1;
        $display("\nTEST 5: MOV r11, r12");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);

        step_and_show;
        expect64("r11 after MOV", dut.reg_file.registers[11],
                 64'h1234_5678_9ABC_DEF0);
        expect64("PC after MOV", dut.fetch.pc, 64'h2004);

        // =========================================================
        // 6) BR r20
        // =========================================================
        reset_core;
        clear_prog_region;
        instr = enc_rrr(OP_BR, 5'd20, 5'd0, 5'd0);
        load_instr(64'h2000, instr);
        set_reg(5'd20, 64'h0000_0000_0000_2030);

        #1;
        $display("\nTEST 6: BR r20");
        show_state;
        expect32("fetched instruction", dut.instruction, instr);

        step_and_show;
        expect64("PC after BR", dut.fetch.pc, 64'h0000_0000_0000_2030);

        // =========================================================
        // Summary
        // =========================================================
        if (fails == 0) begin
            $display("\nALL DEBUG TESTS PASSED");
        end else begin
            $display("\nDEBUG TESTS FAILED: %0d failure(s)", fails);
        end

        $finish;
    end
endmodule