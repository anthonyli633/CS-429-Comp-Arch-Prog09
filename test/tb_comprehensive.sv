`timescale 1ns/1ps

module tb_comprehensive;
    reg clk;
    reg reset;
    integer fails;
    integer fd;
    integer i;

    localparam MEM_SIZE = 512 * 1024;
    localparam SP_INIT  = MEM_SIZE;
    localparam RET_SLOT = MEM_SIZE - 8;

    // Opcodes
    localparam OP_AND       = 5'h00;
    localparam OP_OR        = 5'h01;
    localparam OP_XOR       = 5'h02;
    localparam OP_NOT       = 5'h03;
    localparam OP_SHFTR     = 5'h04;
    localparam OP_SHFTRI    = 5'h05;
    localparam OP_SHFTL     = 5'h06;
    localparam OP_SHFTLI    = 5'h07;
    localparam OP_BR        = 5'h08;
    localparam OP_BRR_REG   = 5'h09;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_CALL      = 5'h0c;
    localparam OP_RETURN    = 5'h0d;
    localparam OP_BRGT      = 5'h0e;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_REG   = 5'h11;
    localparam OP_MOV_LIT   = 5'h12;
    localparam OP_MOV_STORE = 5'h13;
    localparam OP_ADDF      = 5'h14;
    localparam OP_SUBF      = 5'h15;
    localparam OP_MULF      = 5'h16;
    localparam OP_DIVF      = 5'h17;
    localparam OP_ADD       = 5'h18;
    localparam OP_ADDI      = 5'h19;
    localparam OP_SUB       = 5'h1a;
    localparam OP_SUBI      = 5'h1b;
    localparam OP_MUL       = 5'h1c;
    localparam OP_DIV       = 5'h1d;

    tinker_core uut (
        .clk(clk),
        .reset(reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function [31:0] enc_rrr;
        input [4:0] opcode, rd, rs, rt;
        begin
            enc_rrr = {opcode, rd, rs, rt, 12'd0};
        end
    endfunction

    function [31:0] enc_rr;
        input [4:0] opcode, rd, rs;
        begin
            enc_rr = {opcode, rd, rs, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_r;
        input [4:0] opcode, rd;
        begin
            enc_r = {opcode, rd, 5'd0, 5'd0, 12'd0};
        end
    endfunction

    function [31:0] enc_lit;
        input [4:0] opcode;
        input [11:0] lit;
        begin
            enc_lit = {opcode, 5'd0, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_rd_lit;
        input [4:0] opcode, rd;
        input [11:0] lit;
        begin
            enc_rd_lit = {opcode, rd, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_mov_load;
        input [4:0] rd, rs;
        input [11:0] lit;
        begin
            enc_mov_load = {OP_MOV_LOAD, rd, rs, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_mov_store;
        input [4:0] rd, rs;
        input [11:0] lit;
        begin
            enc_mov_store = {OP_MOV_STORE, rd, rs, 5'd0, lit};
        end
    endfunction

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

    function [63:0] read_mem64;
        input [63:0] addr;
        begin
            read_mem64 = {
                uut.memory.bytes[addr+7],
                uut.memory.bytes[addr+6],
                uut.memory.bytes[addr+5],
                uut.memory.bytes[addr+4],
                uut.memory.bytes[addr+3],
                uut.memory.bytes[addr+2],
                uut.memory.bytes[addr+1],
                uut.memory.bytes[addr+0]
            };
        end
    endfunction

    task clear_prog;
        begin
            for (i = 16'h2000; i < 16'h2080; i = i + 1)
                uut.memory.bytes[i] = 8'h00;
        end
    endtask

    task clear_regs_manual;
        begin
            for (i = 0; i < 31; i = i + 1)
                uut.reg_file.registers[i] = 64'd0;
            uut.reg_file.registers[31] = SP_INIT;
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

    task run_one;
        begin
            @(posedge clk); #1;
        end
    endtask

    task expect64;
        input [255:0] name;
        input [63:0] got, exp;
        begin
            if (got !== exp) begin
                fails = fails + 1;
                $display("FAIL %-24s got=%h expected=%h", name, got, exp);
                if (fd) $fdisplay(fd, "FAIL %-24s got=%h expected=%h", name, got, exp);
            end else begin
                $display("PASS %-24s %h", name, got);
                if (fd) $fdisplay(fd, "PASS %-24s %h", name, got);
            end
        end
    endtask

    task expect_nan;
        input [255:0] name;
        input [63:0] got;
        begin
            if ((got[62:52] == 11'h7ff) && (got[51:0] != 0)) begin
                $display("PASS %-24s %h", name, got);
                if (fd) $fdisplay(fd, "PASS %-24s %h", name, got);
            end else begin
                fails = fails + 1;
                $display("FAIL %-24s got=%h expected=NaN", name, got);
                if (fd) $fdisplay(fd, "FAIL %-24s got=%h expected=NaN", name, got);
            end
        end
    endtask

    // Main
    initial begin
        fails = 0;
        reset = 1'b0;

        fd = $fopen("hw8_results.txt", "w");
        if (fd == 0) begin
            $display("ERROR: could not open hw8_results.txt");
            $finish;
        end

        $dumpfile("sim/comprehensive.vcd");
        $dumpvars(0, tb_comprehensive);

        
        // Integer ALU
        
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_AND, 5'd1, 5'd2, 5'd3));
        uut.reg_file.registers[2] = 64'hF0F0_F0F0_F0F0_F0F0;
        uut.reg_file.registers[3] = 64'h0FF0_0FF0_0FF0_0FF0;
        run_one();
        expect64("AND", uut.reg_file.registers[1], 64'h00F0_00F0_00F0_00F0);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_OR, 5'd4, 5'd5, 5'd6));
        uut.reg_file.registers[5] = 64'hF000_0000_0000_000F;
        uut.reg_file.registers[6] = 64'h0F00_0000_0000_00F0;
        run_one();
        expect64("OR", uut.reg_file.registers[4], 64'hFF00_0000_0000_00FF);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_XOR, 5'd7, 5'd8, 5'd9));
        uut.reg_file.registers[8] = 64'd15;
        uut.reg_file.registers[9] = 64'd5;
        run_one();
        expect64("XOR", uut.reg_file.registers[7], 64'd10);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rr(OP_NOT, 5'd10, 5'd11));
        uut.reg_file.registers[11] = 64'h00FF_00FF_00FF_00FF;
        run_one();
        expect64("NOT", uut.reg_file.registers[10], ~64'h00FF_00FF_00FF_00FF);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_SHFTR, 5'd12, 5'd13, 5'd14));
        uut.reg_file.registers[13] = 64'd64;
        uut.reg_file.registers[14] = 64'd3;
        run_one();
        expect64("SHFTR", uut.reg_file.registers[12], 64'd8);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rd_lit(OP_SHFTRI, 5'd15, 12'd2));
        uut.reg_file.registers[15] = 64'd64;
        run_one();
        expect64("SHFTRI", uut.reg_file.registers[15], 64'd16);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_SHFTL, 5'd16, 5'd17, 5'd18));
        uut.reg_file.registers[17] = 64'd7;
        uut.reg_file.registers[18] = 64'd2;
        run_one();
        expect64("SHFTL", uut.reg_file.registers[16], 64'd28);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rd_lit(OP_SHFTLI, 5'd19, 12'd3));
        uut.reg_file.registers[19] = 64'd5;
        run_one();
        expect64("SHFTLI", uut.reg_file.registers[19], 64'd40);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADD, 5'd20, 5'd21, 5'd22));
        uut.reg_file.registers[21] = 64'd10;
        uut.reg_file.registers[22] = 64'd32;
        run_one();
        expect64("ADD", uut.reg_file.registers[20], 64'd42);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd23, 12'd7));
        uut.reg_file.registers[23] = 64'd100;
        run_one();
        expect64("ADDI", uut.reg_file.registers[23], 64'd107);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_SUB, 5'd24, 5'd25, 5'd26));
        uut.reg_file.registers[25] = 64'd50;
        uut.reg_file.registers[26] = 64'd8;
        run_one();
        expect64("SUB", uut.reg_file.registers[24], 64'd42);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rd_lit(OP_SUBI, 5'd27, 12'd8));
        uut.reg_file.registers[27] = 64'd50;
        run_one();
        expect64("SUBI", uut.reg_file.registers[27], 64'd42);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_MUL, 5'd1, 5'd2, 5'd3));
        uut.reg_file.registers[2] = 64'd6;
        uut.reg_file.registers[3] = 64'd7;
        run_one();
        expect64("MUL", uut.reg_file.registers[1], 64'd42);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_DIV, 5'd4, 5'd5, 5'd6));
        uut.reg_file.registers[5] = 64'd84;
        uut.reg_file.registers[6] = 64'd2;
        run_one();
        expect64("DIV", uut.reg_file.registers[4], 64'd42);

         
        // MOVs
         
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rr(OP_MOV_REG, 5'd7, 5'd8));
        uut.reg_file.registers[8] = 64'h1234_5678_9ABC_DEF0;
        run_one();
        expect64("MOV reg", uut.reg_file.registers[7], 64'h1234_5678_9ABC_DEF0);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rd_lit(OP_MOV_LIT, 5'd9, 12'h0A5));
        run_one();
        expect64("MOV literal", uut.reg_file.registers[9], 64'h0000_0000_0000_00A5);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_mov_store(5'd10, 5'd11, 12'h100));
        uut.reg_file.registers[10] = 64'd0;
        uut.reg_file.registers[11] = 64'h1122_3344_5566_7788;
        run_one();
        expect64("MOV store", read_mem64(64'h100), 64'h1122_3344_5566_7788);

        clear_prog(); reset_core();
        write_mem64(64'h108, 64'hDEAD_BEEF_1234_5678);
        write_inst(64'h2000, enc_mov_load(5'd12, 5'd13, 12'h108));
        uut.reg_file.registers[13] = 64'd0;
        run_one();
        expect64("MOV load", uut.reg_file.registers[12], 64'hDEAD_BEEF_1234_5678);

         
        // Branch / control
         
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_r(OP_BR, 5'd20));
        uut.reg_file.registers[20] = 64'h2040;
        run_one();
        expect64("BR", uut.fetch.pc, 64'h2040);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_r(OP_BRR_REG, 5'd21));
        uut.reg_file.registers[21] = 64'd8;
        run_one();
        expect64("BRR reg", uut.fetch.pc, 64'h2008);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_lit(OP_BRR_LIT, 12'd12));
        run_one();
        expect64("BRR literal", uut.fetch.pc, 64'h200C);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd5, 5'd6));
        uut.reg_file.registers[5] = 64'h2030;
        uut.reg_file.registers[6] = 64'd1;
        run_one();
        expect64("BRNZ taken", uut.fetch.pc, 64'h2030);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd5, 5'd6));
        uut.reg_file.registers[5] = 64'h2030;
        uut.reg_file.registers[6] = 64'd0;
        run_one();
        expect64("BRNZ not taken", uut.fetch.pc, 64'h2004);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_r(OP_CALL, 5'd10));
        uut.reg_file.registers[10] = 64'h2050;
        run_one();
        expect64("CALL pc", uut.fetch.pc, 64'h2050);
        expect64("CALL ret save", read_mem64(RET_SLOT), 64'h2004);

        clear_prog(); reset_core();
        write_mem64(RET_SLOT, 64'h2060);
        write_inst(64'h2000, enc_r(OP_RETURN, 5'd0));
        run_one();
        expect64("RETURN", uut.fetch.pc, 64'h2060);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_BRGT, 5'd7, 5'd8, 5'd9));
        uut.reg_file.registers[7] = 64'h2070;
        uut.reg_file.registers[8] = 64'd9;
        uut.reg_file.registers[9] = 64'd3;
        run_one();
        expect64("BRGT taken", uut.fetch.pc, 64'h2070);

        
        // Floating point basics
        
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd1, 5'd2, 5'd3));
        uut.reg_file.registers[2] = 64'h3FF8_0000_0000_0000; // 1.5
        uut.reg_file.registers[3] = 64'h3FF8_0000_0000_0000; // 1.5
        run_one();
        expect64("FADD basic", uut.reg_file.registers[1], 64'h4008_0000_0000_0000); // 3.0

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_SUBF, 5'd4, 5'd5, 5'd6));
        uut.reg_file.registers[5] = 64'h4016_0000_0000_0000; // 5.5
        uut.reg_file.registers[6] = 64'h4002_0000_0000_0000; // 2.25
        run_one();
        expect64("FSUB basic", uut.reg_file.registers[4], 64'h400A_0000_0000_0000); // 3.25

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_MULF, 5'd7, 5'd8, 5'd9));
        uut.reg_file.registers[8] = 64'h4004_0000_0000_0000; // 2.5
        uut.reg_file.registers[9] = 64'h4010_0000_0000_0000; // 4.0
        run_one();
        expect64("FMUL basic", uut.reg_file.registers[7], 64'h4024_0000_0000_0000); // 10.0

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_DIVF, 5'd10, 5'd11, 5'd12));
        uut.reg_file.registers[11] = 64'h401E_0000_0000_0000; // 7.5
        uut.reg_file.registers[12] = 64'h4004_0000_0000_0000; // 2.5
        run_one();
        expect64("FDIV basic", uut.reg_file.registers[10], 64'h4008_0000_0000_0000); // 3.0

        // Rounding
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd13, 5'd14, 5'd15));
        uut.reg_file.registers[14] = 64'h3FF0_0000_0000_0000; // 1.0
        uut.reg_file.registers[15] = 64'h3CA0_0000_0000_0000; // 2^-53
        run_one();
        expect64("FADD rounding", uut.reg_file.registers[13], 64'h3FF0_0000_0000_0000);

        // Subnormal sanity: min subnormal + min subnormal = 2*min subnormal
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd16, 5'd17, 5'd18));
        uut.reg_file.registers[17] = 64'h0000_0000_0000_0001;
        uut.reg_file.registers[18] = 64'h0000_0000_0000_0001;
        run_one();
        expect64("FADD subnormal", uut.reg_file.registers[16], 64'h0000_0000_0000_0002);

        // Infinity / zero / NaN
        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd19, 5'd20, 5'd21));
        uut.reg_file.registers[20] = 64'h7FF0_0000_0000_0000;
        uut.reg_file.registers[21] = 64'h3FF0_0000_0000_0000;
        run_one();
        expect64("FADD +inf", uut.reg_file.registers[19], 64'h7FF0_0000_0000_0000);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_FDIV, 5'd22, 5'd23, 5'd24));
        uut.reg_file.registers[23] = 64'h3FF0_0000_0000_0000;
        uut.reg_file.registers[24] = 64'h0000_0000_0000_0000;
        run_one();
        expect64("FDIV by zero", uut.reg_file.registers[22], 64'h7FF0_0000_0000_0000);

        clear_prog(); reset_core();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd25, 5'd26, 5'd27));
        uut.reg_file.registers[26] = 64'h7FF8_0000_0000_0001;
        uut.reg_file.registers[27] = 64'h3FF0_0000_0000_0000;
        run_one();
        expect_nan("FADD NaN", uut.reg_file.registers[25]);

        // Summary
        if (fails == 0) begin
            $display("\nALL TESTS PASSED");
            $fdisplay(fd, "\nALL TESTS PASSED");
        end else begin
            $display("\nTOTAL FAILS = %0d", fails);
            $fdisplay(fd, "\nTOTAL FAILS = %0d", fails);
        end

        $fclose(fd);
        $finish;
    end
endmodule