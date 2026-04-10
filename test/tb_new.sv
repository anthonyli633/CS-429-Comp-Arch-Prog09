`timescale 1ns/1ps

module tb_new;
    reg clk;
    reg reset;
    integer fails;
    integer cycles;
    integer fd;
    integer i;

    localparam MEM_SIZE = 512 * 1024;
    localparam RET_SLOT = MEM_SIZE - 8;

    // Opcodes
    localparam OP_BR        = 5'h08;
    localparam OP_BRR_LIT   = 5'h0a;
    localparam OP_BRNZ      = 5'h0b;
    localparam OP_CALL      = 5'h0c;
    localparam OP_RETURN    = 5'h0d;
    localparam OP_PRIV      = 5'h0f;
    localparam OP_MOV_LOAD  = 5'h10;
    localparam OP_MOV_STORE = 5'h13;
    localparam OP_ADDF      = 5'h14;
    localparam OP_ADD       = 5'h18;
    localparam OP_ADDI      = 5'h19;
    localparam OP_SUBI      = 5'h1b;

    wire hlt;

    tinker_core dut (
        .clk(clk),
        .reset(reset),
        .hlt(hlt)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Instruction format:
    // [31:27] opcode [26:22] rd [21:17] rs [16:12] rt [11:0] lit
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

    function [31:0] enc_rd_lit;
        input [4:0] opcode, rd;
        input [11:0] lit;
        begin
            enc_rd_lit = {opcode, rd, 5'd0, 5'd0, lit};
        end
    endfunction

    function [31:0] enc_lit;
        input [4:0] opcode;
        input [11:0] lit;
        begin
            enc_lit = {opcode, 5'd0, 5'd0, 5'd0, lit};
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
            dut.memory.bytes[addr+0] = inst[7:0];
            dut.memory.bytes[addr+1] = inst[15:8];
            dut.memory.bytes[addr+2] = inst[23:16];
            dut.memory.bytes[addr+3] = inst[31:24];
        end
    endtask

    task write_mem64;
        input [63:0] addr;
        input [63:0] data;
        begin
            dut.memory.bytes[addr+0] = data[7:0];
            dut.memory.bytes[addr+1] = data[15:8];
            dut.memory.bytes[addr+2] = data[23:16];
            dut.memory.bytes[addr+3] = data[31:24];
            dut.memory.bytes[addr+4] = data[39:32];
            dut.memory.bytes[addr+5] = data[47:40];
            dut.memory.bytes[addr+6] = data[55:48];
            dut.memory.bytes[addr+7] = data[63:56];
        end
    endtask

    function [63:0] read_mem64;
        input [63:0] addr;
        begin
            read_mem64 = {
                dut.memory.bytes[addr+7],
                dut.memory.bytes[addr+6],
                dut.memory.bytes[addr+5],
                dut.memory.bytes[addr+4],
                dut.memory.bytes[addr+3],
                dut.memory.bytes[addr+2],
                dut.memory.bytes[addr+1],
                dut.memory.bytes[addr+0]
            };
        end
    endfunction

    task clear_program_region;
        integer j;
        begin
            for (j = 16'h2000; j < 16'h2080; j = j + 1)
                dut.memory.bytes[j] = 8'h00;
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

    task run_until_halt;
        input integer max_cycles;
        begin
            cycles = 0;
            while (!hlt && cycles < max_cycles) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            #1;
        end
    endtask

    task expect64;
        input [255:0] name;
        input [63:0] got;
        input [63:0] exp;
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

    task expect_true;
        input [255:0] name;
        input cond;
        begin
            if (!cond) begin
                fails = fails + 1;
                $display("FAIL %-24s", name);
                if (fd) $fdisplay(fd, "FAIL %-24s", name);
            end else begin
                $display("PASS %-24s", name);
                if (fd) $fdisplay(fd, "PASS %-24s", name);
            end
        end
    endtask

    initial begin
        fails = 0;
        reset = 1'b0;
        cycles = 0;

        fd = $fopen("hw9_results.txt", "w");
        if (fd == 0) begin
            $display("ERROR: could not open hw9_results.txt");
            $finish;
        end

        $dumpfile("new.vcd");
        $dumpvars(0, tb_new);

        // Test 0: Reset behavior
        clear_program_region();
        do_reset();
        expect64("reset pc", dut.fetch.pc, 64'h0000_0000_0000_2000);
        expect64("reset r31", dut.reg_file.registers[31], MEM_SIZE);
        expect64("reset r0", dut.reg_file.registers[0], 64'd0);
        expect_true("reset hlt low", hlt == 1'b0);

        // Test 1: Halt only
        clear_program_region();
        write_inst(64'h2000, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(20);
        expect_true("halt reached", hlt == 1'b1);
        expect_true("halt multicycle", cycles >= 2);

        // Test 2: Integer ALU program
        // r1=5, r2=7, r3=r1+r2, r3=r3-2, halt
        clear_program_region();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'd5));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd7));
        write_inst(64'h2008, enc_rrr(OP_ADD, 5'd3, 5'd1, 5'd2));
        write_inst(64'h200C, enc_rd_lit(OP_SUBI, 5'd3, 12'd2));
        write_inst(64'h2010, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect_true("alu halt", hlt == 1'b1);
        expect64("alu result r3", dut.reg_file.registers[3], 64'd10);
        expect_true("alu multicycle", cycles >= 10);

        // Test 3: Store then load through memory
        // r1 = 0x100, r2 = 42, store r2 -> mem[r1], load mem[r1] -> r3
        clear_program_region();
        write_inst(64'h2000, enc_rd_lit(OP_ADDI, 5'd1, 12'h100));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd2, 12'd42));
        write_inst(64'h2008, enc_mov_store(5'd1, 5'd2, 12'd0));
        write_inst(64'h200C, enc_mov_load(5'd3, 5'd1, 12'd0));
        write_inst(64'h2010, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(100);
        expect64("store mem[0x100]", read_mem64(64'h100), 64'd42);
        expect64("load result r3", dut.reg_file.registers[3], 64'd42);

        // Test 4: BRNZ taken
        // branch target is preloaded into r4 after reset
        clear_program_region();
        write_inst(64'h2000, enc_rr(OP_BRNZ, 5'd4, 5'd5));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd6, 12'd1));  // should skip
        write_inst(64'h2010, enc_rd_lit(OP_ADDI, 5'd6, 12'd9));
        write_inst(64'h2014, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[4] = 64'h0000_0000_0000_2010;
        dut.reg_file.registers[5] = 64'd1;
        run_until_halt(80);
        expect64("brnz target result", dut.reg_file.registers[6], 64'd9);

        // Test 5: BRR literal
        // jump from 0x2000 to 0x2008
        clear_program_region();
        write_inst(64'h2000, enc_lit(OP_BRR_LIT, 12'd8));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd7, 12'd1));  // should skip
        write_inst(64'h2008, enc_rd_lit(OP_ADDI, 5'd7, 12'd9));
        write_inst(64'h200C, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        run_until_halt(80);
        expect64("brr literal result", dut.reg_file.registers[7], 64'd9);

        // Test 6: CALL + RETURN
        // call target in r10 is preloaded after reset
        clear_program_region();
        write_inst(64'h2000, enc_r(OP_CALL, 5'd10));
        write_inst(64'h2004, enc_rd_lit(OP_ADDI, 5'd8, 12'd1));
        write_inst(64'h2008, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        write_inst(64'h2010, enc_r(OP_RETURN, 5'd0));
        do_reset();
        dut.reg_file.registers[10] = 64'h0000_0000_0000_2010;
        run_until_halt(120);
        expect64("call return r8", dut.reg_file.registers[8], 64'd1);
        expect64("call saved return", read_mem64(RET_SLOT), 64'h0000_0000_0000_2004);

        // Test 7: FP add
        clear_program_region();
        write_inst(64'h2000, enc_rrr(OP_ADDF, 5'd3, 5'd1, 5'd2));
        write_inst(64'h2004, {OP_PRIV, 5'd0, 5'd0, 5'd0, 12'h000});
        do_reset();
        dut.reg_file.registers[1] = 64'h3FF8_0000_0000_0000;
        dut.reg_file.registers[2] = 64'h3FF8_0000_0000_0000;
        run_until_halt(60);
        expect64("fadd basic", dut.reg_file.registers[3], 64'h4008_0000_0000_0000);

        if (fails == 0) begin
            $display("\nALL MULTICYCLE TESTS PASSED");
            $fdisplay(fd, "ALL MULTICYCLE TESTS PASSED");
        end else begin
            $display("\nTOTAL FAILS = %0d", fails);
            $fdisplay(fd, "TOTAL FAILS = %0d", fails);
        end

        $fclose(fd);
        $finish;
    end
endmodule
