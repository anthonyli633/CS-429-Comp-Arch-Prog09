`timescale 1ns/1ps

module tinker_alu_fpu(
    input  [63:0] a,
    input  [63:0] b,
    input  [5:0]  op,
    output reg [63:0] result,
    output wire a_is_zero,
    output wire a_gt_b_signed
);
    localparam ALU_PASS_A = 6'd0;
    localparam ALU_PASS_B = 6'd1;
    localparam ALU_AND    = 6'd2;
    localparam ALU_OR     = 6'd3;
    localparam ALU_XOR    = 6'd4;
    localparam ALU_NOT    = 6'd5;
    localparam ALU_SHR    = 6'd6;
    localparam ALU_SHL    = 6'd7;
    localparam ALU_ADD    = 6'd8;
    localparam ALU_SUB    = 6'd9;
    localparam ALU_MUL    = 6'd10;
    localparam ALU_DIV    = 6'd11;
    localparam ALU_FADD   = 6'd12;
    localparam ALU_FSUB   = 6'd13;
    localparam ALU_FMUL   = 6'd14;
    localparam ALU_FDIV   = 6'd15;

    localparam QUIET_NAN  = 64'h7ff8_0000_0000_0000;

    assign a_is_zero      = (a == 64'd0);
    assign a_gt_b_signed  = ($signed(a) > $signed(b));

    function automatic is_nan64(input [63:0] x);
        begin
            is_nan64 = (x[62:52] == 11'h7ff) && (x[51:0] != 0);
        end
    endfunction

    function automatic is_inf64(input [63:0] x);
        begin
            is_inf64 = (x[62:52] == 11'h7ff) && (x[51:0] == 0);
        end
    endfunction

    function automatic is_zero64(input [63:0] x);
        begin
            is_zero64 = (x[62:52] == 0) && (x[51:0] == 0);
        end
    endfunction

    function automatic [63:0] pack_fp;
        input sign;
        input integer exp_unbiased;
        input [52:0] sig;
        begin
            if (sig == 0) begin
                pack_fp = 64'd0;
            end else if (exp_unbiased + 1023 >= 2047) begin
                pack_fp = {sign, 11'h7ff, 52'd0};
            end else if (exp_unbiased + 1023 <= 0) begin
                pack_fp = 64'd0; // TODO: Subnormals
            end else begin
                pack_fp = {sign, exp_unbiased[10:0] + 11'd1023, sig[51:0]};
            end
        end
    endfunction

    function automatic [63:0] fp_addsub64;
        input [63:0] x;
        input [63:0] y;
        input sub;
        reg sx, sy, sr;
        reg [10:0] ex, ey;
        reg [51:0] fx, fy;
        reg [52:0] mx, my, mr;
        integer e1, e2, er, shift, i;
        reg [63:0] y2;
        begin
            y2 = sub ? {~y[63], y[62:0]} : y;

            if (is_nan64(x) || is_nan64(y2)) begin
                fp_addsub64 = QUIET_NAN;
            end else if (is_inf64(x) && is_inf64(y2) && (x[63] != y2[63])) begin
                fp_addsub64 = QUIET_NAN;
            end else if (is_inf64(x)) begin
                fp_addsub64 = x;
            end else if (is_inf64(y2)) begin
                fp_addsub64 = y2;
            end else if (is_zero64(x)) begin
                fp_addsub64 = y2;
            end else if (is_zero64(y2)) begin
                fp_addsub64 = x;
            end else begin
                sx = x[63]; sy = y2[63];
                ex = x[62:52]; ey = y2[62:52];
                fx = x[51:0]; fy = y2[51:0];

                // Subnormals = 0 for now
                if (ex == 0 || ey == 0) begin
                    fp_addsub64 = 64'd0;
                end else begin
                    e1 = ex - 1023;
                    e2 = ey - 1023;
                    mx = {1'b1, fx};
                    my = {1'b1, fy};

                    if (e1 > e2) begin
                        shift = e1 - e2;
                        if (shift > 52) my = 0;
                        else my = my >> shift;
                        er = e1;
                    end else if (e2 > e1) begin
                        shift = e2 - e1;
                        if (shift > 52) mx = 0;
                        else mx = mx >> shift;
                        er = e2;
                    end else begin
                        er = e1;
                    end

                    if (sx == sy) begin
                        mr = mx + my;
                        sr = sx;
                        if (mr[52]) begin
                            // already normalized or overflowed into bit 52
                        end
                        if (mr[52] && (mr >= 53'h2_0000_0000_0000)) begin
                            mr = mr >> 1;
                            er = er + 1;
                        end
                    end else begin
                        if (mx >= my) begin
                            mr = mx - my;
                            sr = sx;
                        end else begin
                            mr = my - mx;
                            sr = sy;
                        end

                        if (mr == 0) begin
                            fp_addsub64 = 64'd0;
                        end

                        while ((mr[52] == 0) && (er > -1022)) begin
                            mr = mr << 1;
                            er = er - 1;
                        end
                    end

                    fp_addsub64 = pack_fp(sr, er, mr);
                end
            end
        end
    endfunction

    function automatic [63:0] fp_mul64;
        input [63:0] x;
        input [63:0] y;
        reg sx, sy, sr;
        reg [10:0] ex, ey;
        reg [51:0] fx, fy;
        reg [52:0] mx, my, mr;
        reg [105:0] prod;
        integer er;
        begin
            if (is_nan64(x) || is_nan64(y)) begin
                fp_mul64 = QUIET_NAN;
            end else if ((is_inf64(x) && is_zero64(y)) || (is_inf64(y) && is_zero64(x))) begin
                fp_mul64 = QUIET_NAN;
            end else if (is_inf64(x) || is_inf64(y)) begin
                fp_mul64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_zero64(x) || is_zero64(y)) begin
                fp_mul64 = {x[63]^y[63], 63'd0};
            end else begin
                sx = x[63]; sy = y[63]; sr = sx ^ sy;
                ex = x[62:52]; ey = y[62:52];
                fx = x[51:0]; fy = y[51:0];

                if (ex == 0 || ey == 0) begin
                    fp_mul64 = 64'd0; // ignore subnormals for now
                end else begin
                    mx = {1'b1, fx};
                    my = {1'b1, fy};
                    prod = mx * my;
                    er = (ex - 1023) + (ey - 1023);

                    if (prod[105]) begin
                        mr = prod[105:53];
                        er = er + 1;
                    end else begin
                        mr = prod[104:52];
                    end

                    fp_mul64 = pack_fp(sr, er, mr);
                end
            end
        end
    endfunction

    function automatic [63:0] fp_div64;
        input [63:0] x;
        input [63:0] y;
        reg sx, sy, sr;
        reg [10:0] ex, ey;
        reg [51:0] fx, fy;
        reg [52:0] mx, my, mr;
        reg [105:0] num;
        integer er;
        begin
            if (is_nan64(x) || is_nan64(y)) begin
                fp_div64 = QUIET_NAN;
            end else if ((is_inf64(x) && is_inf64(y)) || (is_zero64(x) && is_zero64(y))) begin
                fp_div64 = QUIET_NAN;
            end else if (is_inf64(x)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_inf64(y)) begin
                fp_div64 = {x[63]^y[63], 63'd0};
            end else if (is_zero64(y)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};
            end else if (is_zero64(x)) begin
                fp_div64 = {x[63]^y[63], 63'd0};
            end else begin
                sx = x[63]; sy = y[63]; sr = sx ^ sy;
                ex = x[62:52]; ey = y[62:52];
                fx = x[51:0]; fy = y[51:0];

                if (ex == 0 || ey == 0) begin
                    fp_div64 = 64'd0; // ignore subnormals for now
                end else begin
                    mx = {1'b1, fx};
                    my = {1'b1, fy};
                    er = (ex - 1023) - (ey - 1023);

                    num = ({53'd0, mx} << 52);
                    mr = num / my;

                    if (mr[52] == 0) begin
                        mr = mr << 1;
                        er = er - 1;
                    end

                    fp_div64 = pack_fp(sr, er, mr);
                end
            end
        end
    endfunction

    always @(*) begin
        case (op)
            ALU_PASS_A: result = a;
            ALU_PASS_B: result = b;
            ALU_AND   : result = a & b;
            ALU_OR    : result = a | b;
            ALU_XOR   : result = a ^ b;
            ALU_NOT   : result = ~a;
            ALU_SHR   : result = a >> b[5:0];
            ALU_SHL   : result = a << b[5:0];
            ALU_ADD   : result = $signed(a) + $signed(b);
            ALU_SUB   : result = $signed(a) - $signed(b);
            ALU_MUL   : result = $signed(a) * $signed(b);
            ALU_DIV   : result = (b == 64'd0) ? 64'd0 : $signed(a) / $signed(b);
            ALU_FADD  : result = fp_addsub64(a, b, 1'b0);
            ALU_FSUB  : result = fp_addsub64(a, b, 1'b1);
            ALU_FMUL  : result = fp_mul64(a, b);
            ALU_FDIV  : result = fp_div64(a, b);
            default   : result = 64'd0;
        endcase
    end
endmodule