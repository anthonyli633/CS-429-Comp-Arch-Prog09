`timescale 1ns/1ps

module tinker_memory #(
    parameter MEM_SIZE = 512 * 1024
)(
    input         clk,
    input  [63:0] inst_addr,
    output [31:0] inst_word,
    input  [63:0] data_addr,
    input  [63:0] data_write_data,
    input         data_write_en,
    output [63:0] data_read_data
);
    reg [7:0] bytes [0:MEM_SIZE-1];

    wire [31:0] inst_idx = inst_addr[31:0];
    wire [31:0] data_idx = data_addr[31:0];

    assign inst_word =
        (inst_idx + 32'd3 < MEM_SIZE) ?
        {bytes[inst_idx + 32'd3],
         bytes[inst_idx + 32'd2],
         bytes[inst_idx + 32'd1],
         bytes[inst_idx + 32'd0]} :
        32'd0;

    assign data_read_data =
        (data_idx + 32'd7 < MEM_SIZE) ?
        {bytes[data_idx + 32'd7],
         bytes[data_idx + 32'd6],
         bytes[data_idx + 32'd5],
         bytes[data_idx + 32'd4],
         bytes[data_idx + 32'd3],
         bytes[data_idx + 32'd2],
         bytes[data_idx + 32'd1],
         bytes[data_idx + 32'd0]} :
        64'd0;

    always @(posedge clk) begin
        if (data_write_en && (data_idx + 32'd7 < MEM_SIZE)) begin
            bytes[data_idx + 32'd0] <= data_write_data[7:0];
            bytes[data_idx + 32'd1] <= data_write_data[15:8];
            bytes[data_idx + 32'd2] <= data_write_data[23:16];
            bytes[data_idx + 32'd3] <= data_write_data[31:24];
            bytes[data_idx + 32'd4] <= data_write_data[39:32];
            bytes[data_idx + 32'd5] <= data_write_data[47:40];
            bytes[data_idx + 32'd6] <= data_write_data[55:48];
            bytes[data_idx + 32'd7] <= data_write_data[63:56];
        end
    end
endmodule