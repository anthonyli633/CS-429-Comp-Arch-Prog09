`timescale 1ns/1ps

module tinker_core (
    input clk,
    input reset,
    output logic hlt
);
    localparam MEM_SIZE = 512 * 1024;

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

    localparam ALU_PASS_A   = 6'd0;
    localparam ALU_PASS_B   = 6'd1;
    localparam ALU_AND      = 6'd2;
    localparam ALU_OR       = 6'd3;
    localparam ALU_XOR      = 6'd4;
    localparam ALU_NOT      = 6'd5;
    localparam ALU_SHR      = 6'd6;
    localparam ALU_SHL      = 6'd7;
    localparam ALU_ADD      = 6'd8;
    localparam ALU_SUB      = 6'd9;
    localparam ALU_MUL      = 6'd10;
    localparam ALU_DIV      = 6'd11;
    localparam ALU_FADD     = 6'd12;
    localparam ALU_FSUB     = 6'd13;
    localparam ALU_FMUL     = 6'd14;
    localparam ALU_FDIV     = 6'd15;

    localparam S_FETCH      = 4'd0;
    localparam S_DECODE     = 4'd1;
    localparam S_EXEC_ALU   = 4'd2;
    localparam S_WB_ALU     = 4'd3;
    localparam S_ADDR       = 4'd4;
    localparam S_MEM_READ   = 4'd5;
    localparam S_WB_MEM     = 4'd6;
    localparam S_MEM_WRITE  = 4'd7;
    localparam S_BRANCH     = 4'd8;
    localparam S_CALL       = 4'd9;
    localparam S_RETURN     = 4'd10;
    localparam S_HALT       = 4'd11;

    reg [3:0]  state, next_state;
    reg [31:0] ir;
    reg [63:0] ir_pc;
    reg [63:0] rd_latch, rs_latch, rt_latch;
    reg [63:0] ALUOut;
    reg [63:0] MDR;

    wire [63:0] pc;
    wire [31:0] instruction;

    wire [4:0]  opcode;
    wire [4:0]  rd_idx;
    wire [4:0]  rs_idx;
    wire [4:0]  rt_idx;
    wire [11:0] lit12;
    wire [63:0] lit_zext;
    wire [63:0] lit_sext;

    wire [63:0] rd_data;
    wire [63:0] rs_data;
    wire [63:0] rt_data;
    wire [63:0] sp_data;

    reg         rf_write_en;
    reg  [4:0]  rf_write_addr;
    reg  [63:0] rf_write_data;

    reg         data_write_en;
    reg  [63:0] data_addr;
    reg  [63:0] data_write_data;
    wire [63:0] data_read_data;

    reg         pc_write;
    reg  [63:0] pc_next;

    reg  [5:0]  alu_op;
    reg  [63:0] alu_a;
    reg  [63:0] alu_b;
    wire [63:0] alu_result;
    wire        alu_a_is_zero;
    wire        alu_a_gt_b_signed;

    tinker_memory #( .MEM_SIZE(MEM_SIZE) ) memory (
        .clk(clk),
        .inst_addr(pc),
        .inst_word(instruction),
        .data_addr(data_addr),
        .data_write_data(data_write_data),
        .data_write_en(data_write_en),
        .data_read_data(data_read_data)
    );

    tinker_fetch fetch (
        .clk(clk),
        .reset(reset),
        .pc_write(pc_write),
        .pc_next(pc_next),
        .pc(pc)
    );

    tinker_decoder decoder (
        .instruction(ir),
        .opcode(opcode),
        .rd_idx(rd_idx),
        .rs_idx(rs_idx),
        .rt_idx(rt_idx),
        .lit12(lit12),
        .lit_zext(lit_zext),
        .lit_sext(lit_sext)
    );

    tinker_reg_file #( .MEM_SIZE(MEM_SIZE) ) reg_file (
        .clk(clk),
        .reset(reset),
        .read_addr_a(rd_idx),
        .read_addr_b(rs_idx),
        .read_addr_c(rt_idx),
        .read_data_a(rd_data),
        .read_data_b(rs_data),
        .read_data_c(rt_data),
        .sp_data(sp_data),
        .write_en(rf_write_en),
        .write_addr(rf_write_addr),
        .write_data(rf_write_data)
    );

    tinker_alu_fpu alu_fpu (
        .a(alu_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result),
        .a_is_zero(alu_a_is_zero),
        .a_gt_b_signed(alu_a_gt_b_signed)
    );

    always @(*) begin
        hlt              = (state == S_HALT);
        next_state       = state;

        rf_write_en      = 1'b0;
        rf_write_addr    = rd_idx;
        rf_write_data    = 64'd0;

        data_write_en    = 1'b0;
        data_addr        = 64'd0;
        data_write_data  = 64'd0;

        pc_write         = 1'b0;
        pc_next          = pc;

        alu_op           = ALU_PASS_A;
        alu_a            = 64'd0;
        alu_b            = 64'd0;

        case (state)
            S_FETCH: begin
                pc_write   = 1'b1;
                pc_next    = pc + 64'd4;
                next_state = S_DECODE;
            end

            S_DECODE: begin
                if (opcode == OP_PRIV && lit12 == 12'h000)
                    next_state = S_HALT;
                else if (opcode == OP_MOV_LOAD || opcode == OP_MOV_STORE)
                    next_state = S_ADDR;
                else if (opcode == OP_BR || opcode == OP_BRR_REG || opcode == OP_BRR_LIT ||
                         opcode == OP_BRNZ || opcode == OP_BRGT)
                    next_state = S_BRANCH;
                else if (opcode == OP_CALL)
                    next_state = S_CALL;
                else if (opcode == OP_RETURN)
                    next_state = S_RETURN;
                else
                    next_state = S_EXEC_ALU;
            end

            S_EXEC_ALU: begin
                case (opcode)
                    OP_AND:    begin alu_op = ALU_AND;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_OR:     begin alu_op = ALU_OR;   alu_a = rs_latch; alu_b = rt_latch; end
                    OP_XOR:    begin alu_op = ALU_XOR;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_NOT:    begin alu_op = ALU_NOT;  alu_a = rs_latch; end
                    OP_SHFTR:  begin alu_op = ALU_SHR;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_SHFTRI: begin alu_op = ALU_SHR;  alu_a = rd_latch; alu_b = lit_zext; end
                    OP_SHFTL:  begin alu_op = ALU_SHL;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_SHFTLI: begin alu_op = ALU_SHL;  alu_a = rd_latch; alu_b = lit_zext; end
                    OP_MOV_REG:begin alu_op = ALU_PASS_A; alu_a = rs_latch; end
                    OP_MOV_LIT:begin alu_op = ALU_PASS_A; alu_a = lit_zext; end
                    OP_ADDF:   begin alu_op = ALU_FADD; alu_a = rs_latch; alu_b = rt_latch; end
                    OP_SUBF:   begin alu_op = ALU_FSUB; alu_a = rs_latch; alu_b = rt_latch; end
                    OP_MULF:   begin alu_op = ALU_FMUL; alu_a = rs_latch; alu_b = rt_latch; end
                    OP_DIVF:   begin alu_op = ALU_FDIV; alu_a = rs_latch; alu_b = rt_latch; end
                    OP_ADD:    begin alu_op = ALU_ADD;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_ADDI:   begin alu_op = ALU_ADD;  alu_a = rd_latch; alu_b = lit_zext; end
                    OP_SUB:    begin alu_op = ALU_SUB;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_SUBI:   begin alu_op = ALU_SUB;  alu_a = rd_latch; alu_b = lit_zext; end
                    OP_MUL:    begin alu_op = ALU_MUL;  alu_a = rs_latch; alu_b = rt_latch; end
                    OP_DIV:    begin alu_op = ALU_DIV;  alu_a = rs_latch; alu_b = rt_latch; end
                    default:   begin alu_op = ALU_PASS_A; alu_a = 64'd0; end
                endcase
                next_state = S_WB_ALU;
            end

            S_WB_ALU: begin
                if (opcode != OP_PRIV) begin
                    rf_write_en   = 1'b1;
                    rf_write_addr = rd_idx;
                    rf_write_data = ALUOut;
                end
                next_state = S_FETCH;
            end

            S_ADDR: begin
                alu_op = ALU_ADD;
                if (opcode == OP_MOV_LOAD)
                    alu_a = rs_latch;
                else
                    alu_a = rd_latch;
                alu_b = lit_sext;

                if (opcode == OP_MOV_LOAD)
                    next_state = S_MEM_READ;
                else
                    next_state = S_MEM_WRITE;
            end

            S_MEM_READ: begin
                data_addr   = ALUOut;
                next_state  = S_WB_MEM;
            end

            S_WB_MEM: begin
                rf_write_en   = 1'b1;
                rf_write_addr = rd_idx;
                rf_write_data = MDR;
                next_state    = S_FETCH;
            end

            S_MEM_WRITE: begin
                data_addr       = ALUOut;
                data_write_en   = 1'b1;
                data_write_data = rs_latch;
                next_state      = S_FETCH;
            end

            S_BRANCH: begin
                case (opcode)
                    OP_BR: begin
                        pc_write = 1'b1;
                        pc_next  = rd_latch;
                    end
                    OP_BRR_REG: begin
                        pc_write = 1'b1;
                        pc_next  = ir_pc + rd_latch;
                    end
                    OP_BRR_LIT: begin
                        pc_write = 1'b1;
                        pc_next  = ir_pc + lit_sext;
                    end
                    OP_BRNZ: begin
                        if (rs_latch != 64'd0) begin
                            pc_write = 1'b1;
                            pc_next  = rd_latch;
                        end
                    end
                    OP_BRGT: begin
                        if ($signed(rs_latch) > $signed(rt_latch)) begin
                            pc_write = 1'b1;
                            pc_next  = rd_latch;
                        end
                    end
                    default: begin end
                endcase
                next_state = S_FETCH;
            end

            S_CALL: begin
                data_write_en   = 1'b1;
                data_addr       = sp_data - 64'd8;
                data_write_data = ir_pc + 64'd4;
                pc_write        = 1'b1;
                pc_next         = rd_latch;
                next_state      = S_FETCH;
            end

            S_RETURN: begin
                data_addr  = sp_data - 64'd8;
                pc_write   = 1'b1;
                pc_next    = data_read_data;
                next_state = S_FETCH;
            end

            S_HALT: begin
                next_state = S_HALT;
            end

            default: begin
                next_state = S_FETCH;
            end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state    <= S_FETCH;
            ir       <= 32'd0;
            ir_pc    <= 64'd0;
            rd_latch <= 64'd0;
            rs_latch <= 64'd0;
            rt_latch <= 64'd0;
            ALUOut   <= 64'd0;
            MDR      <= 64'd0;
        end else begin
            state <= next_state;
            case (state)
                S_FETCH: begin
                    ir    <= instruction;
                    ir_pc <= pc;
                end
                S_DECODE: begin
                    rd_latch <= rd_data;
                    rs_latch <= rs_data;
                    rt_latch <= rt_data;
                end
                S_EXEC_ALU: begin
                    ALUOut <= alu_result;
                end
                S_ADDR: begin
                    ALUOut <= alu_result;
                end
                S_MEM_READ: begin
                    MDR <= data_read_data;
                end
                default: begin end
            endcase
        end
    end
endmodule
