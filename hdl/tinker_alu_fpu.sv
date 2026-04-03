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

    assign a_is_zero     = (a == 64'd0);
    assign a_gt_b_signed = ($signed(a) > $signed(b));

    function automatic is_nan64(input [63:0] x);
        begin is_nan64 = (x[62:52] == 11'h7ff) && (x[51:0] != 0); end
    endfunction

    function automatic is_inf64(input [63:0] x);
        begin is_inf64 = (x[62:52] == 11'h7ff) && (x[51:0] == 0); end
    endfunction

    function automatic is_zero64(input [63:0] x);
        begin is_zero64 = (x[62:52] == 0) && (x[51:0] == 0); end
    endfunction

    function automatic [55:0] shr_sticky56;
        input [55:0] x;
        input integer sh;
        reg [55:0] tmp;
        reg sticky;
        integer i;
        begin
            if (sh <= 0) begin
                shr_sticky56 = x;
            end else if (sh >= 56) begin
                shr_sticky56 = (x != 0) ? 56'd1 : 56'd0;
            end else begin
                tmp = x >> sh;
                sticky = 1'b0;
                for (i = 0; i < sh; i = i + 1)
                    sticky = sticky | x[i];
                tmp[0] = tmp[0] | sticky;
                shr_sticky56 = tmp;
            end
        end
    endfunction

    function automatic [63:0] pack_rne64;
        input sign;
        input integer exp_unbiased;
        input [55:0] ext;   // {53 sig bits, guard, round, sticky}
        reg [55:0] ext_r;
        reg [52:0] sig_main;
        reg guard, roundb, sticky;
        reg inc;
        reg [53:0] sig_round;
        integer exp_r, sh;
        begin
            ext_r = ext;
            exp_r = exp_unbiased;

            if ((exp_r < -1022) || ((exp_r == -1022) && (ext_r[55] == 1'b0))) begin
                sh = -1022 - exp_r;
                if (sh < 0) sh = 0;
                ext_r = shr_sticky56(ext_r, sh);
                exp_r = -1022;
            end

            sig_main = ext_r[55:3];
            guard    = ext_r[2];
            roundb   = ext_r[1];
            sticky   = ext_r[0];

            inc = guard && (roundb || sticky || sig_main[0]); // rounding
            sig_round = {1'b0, sig_main} + inc;

            if (sig_round == 0) begin
                pack_rne64 = 64'd0;
            end else if (sig_round[53]) begin
                sig_round = sig_round >> 1;
                exp_r = exp_r + 1;
                if (exp_r + 1023 >= 2047)
                    pack_rne64 = {sign, 11'h7ff, 52'd0};
                else
                    pack_rne64 = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};
            end else if ((exp_r == -1022) && (sig_round[52] == 1'b0)) begin
                pack_rne64 = {sign, 11'd0, sig_round[51:0]};   // subnormal
            end else if (exp_r + 1023 >= 2047) begin
                pack_rne64 = {sign, 11'h7ff, 52'd0};
            end else begin
                pack_rne64 = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};
            end
        end
    endfunction

    function automatic [63:0] fp_addsub64;
        input [63:0] x;
        input [63:0] y;
        input sub;
        reg [63:0] y2;
        reg sx, sy, sr, s_big, s_small;
        reg [10:0] ex, ey;
        reg [51:0] fx, fy;
        reg [52:0] mx, my, m_big, m_small;
        reg [55:0] ex_big, ex_small, ex_res;
        reg [56:0] sum57;
        integer e1, e2, er, sh;
        integer e_big, e_small;
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
            end else if (is_zero64(x) && is_zero64(y2)) begin
                fp_addsub64 = 64'd0;
            end else begin
                sx = x[63]; sy = y2[63];
                ex = x[62:52]; ey = y2[62:52];
                fx = x[51:0]; fy = y2[51:0];

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, fx} : {1'b1, fx};
                my = (ey == 0) ? {1'b0, fy} : {1'b1, fy};

                if ((e1 > e2) || ((e1 == e2) && (mx >= my))) begin
                    e_big   = e1; m_big = mx; s_big = sx;
                    e_small = e2; m_small = my; s_small = sy;
                end else begin
                    e_big   = e2; m_big = my; s_big = sy;
                    e_small = e1; m_small = mx; s_small = sx;
                end

                er = e_big;
                ex_big = {m_big, 3'b000};
                sh = e_big - e_small;
                ex_small = shr_sticky56({m_small, 3'b000}, sh);

                if (s_big == s_small) begin
                    sum57 = {1'b0, ex_big} + {1'b0, ex_small};
                    sr = s_big;
                    if (sum57[56]) begin
                        ex_res = sum57[56:1];
                        ex_res[0] = ex_res[0] | sum57[0];
                        er = er + 1;
                    end else begin
                        ex_res = sum57[55:0];
                    end
                end else begin
                    ex_res = ex_big - ex_small;
                    sr = s_big;
                    if (ex_res == 0) begin
                        fp_addsub64 = 64'd0;
                    end
                    while ((ex_res[55] == 1'b0) && (er > -1022)) begin
                        ex_res = ex_res << 1;
                        er = er - 1;
                    end
                end

                fp_addsub64 = pack_rne64(sr, er, ex_res);
            end
        end
    endfunction

    function automatic [63:0] fp_mul64;
        input [63:0] x;
        input [63:0] y;
        reg sx, sy, sr;
        reg [10:0] ex, ey;
        reg [52:0] mx, my;
        reg [105:0] prod;
        reg [55:0] ext;
        integer e1, e2, er;
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

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, x[51:0]} : {1'b1, x[51:0]};
                my = (ey == 0) ? {1'b0, y[51:0]} : {1'b1, y[51:0]};

                prod = mx * my;
                er = e1 + e2;

                if (prod[105]) begin
                    ext = {prod[105:53], prod[52], prod[51], |prod[50:0]};
                    er = er + 1;
                end else begin
                    ext = {prod[104:52], prod[51], prod[50], |prod[49:0]};
                end

                fp_mul64 = pack_rne64(sr, er, ext);
            end
        end
    endfunction

    function automatic [63:0] fp_div64;
        input [63:0] x;
        input [63:0] y;
        reg sx, sy, sr;
        reg [10:0] ex, ey;
        reg [52:0] mx, my;
        reg [107:0] num;
        reg [55:0] q;
        reg [52:0] rem;
        integer e1, e2, er;
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

                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                mx = (ex == 0) ? {1'b0, x[51:0]} : {1'b1, x[51:0]};
                my = (ey == 0) ? {1'b0, y[51:0]} : {1'b1, y[51:0]};

                er = e1 - e2;
                num = {mx, 55'd0};
                q = num / my;
                rem = num % my;

                if (q[55] == 1'b0) begin
                    q = q << 1;
                    er = er - 1;
                end
                q[0] = q[0] | (rem != 0);

                fp_div64 = pack_rne64(sr, er, q);
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