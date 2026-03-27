`timescale 1ns/1ps

module tb_tinker_smoke;
    reg clk;
    reg reset;

    tinker_core dut (
        .clk(clk),
        .reset(reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        reset = 1'b1;

        @(posedge clk);
        #1;

        if (dut.fetch.pc !== 64'h0000_0000_0000_2000) begin
            $display("FAIL: PC after reset = %h", dut.fetch.pc);
            $finish;
        end

        if (dut.reg_file.registers[31] !== 64'd524288) begin
            $display("FAIL: r31 after reset = %h", dut.reg_file.registers[31]);
            $finish;
        end

        if (dut.reg_file.registers[0] !== 64'd0) begin
            $display("FAIL: r0 after reset = %h", dut.reg_file.registers[0]);
            $finish;
        end

        reset = 1'b0;

        @(posedge clk);
        #1;

        if (dut.fetch.pc !== 64'h0000_0000_0000_2004) begin
            $display("FAIL: PC after one cycle = %h", dut.fetch.pc);
            $finish;
        end

        $display("PASS");
        $finish;
    end
endmodule