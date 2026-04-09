`timescale 1ns/1ps

module tinker_reg_file #(
    parameter MEM_SIZE = 512 * 1024
)(
    input         clk,
    input         reset,
    input  [4:0]  read_addr_a,
    input  [4:0]  read_addr_b,
    input  [4:0]  read_addr_c,
    output [63:0] read_data_a,
    output [63:0] read_data_b,
    output [63:0] read_data_c,
    output [63:0] sp_data,
    input         write_en,
    input  [4:0]  write_addr,
    input  [63:0] write_data
);
    reg [63:0] registers [0:31];
    integer i;

    assign read_data_a = registers[read_addr_a];
    assign read_data_b = registers[read_addr_b];
    assign read_data_c = registers[read_addr_c];
    assign sp_data     = registers[31];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 31; i = i + 1)
                registers[i] <= 64'd0;
            registers[31] <= MEM_SIZE;
        end else begin
            if (write_en)
                registers[write_addr] <= write_data;
            registers[0] <= 64'd0;
        end
    end
endmodule
