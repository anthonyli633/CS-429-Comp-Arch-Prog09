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

    // HELPERS
    assign a_is_zero     = (a == 64'd0);
    assign a_gt_b_signed = ($signed(a) > $signed(b));

    // NAN: exponent = all 1s and fraction != 0
    function automatic is_nan64(input [63:0] x);
        begin is_nan64 = (x[62:52] == 11'h7ff) && (x[51:0] != 0); end
    endfunction

    // INF: exponent = all 1s and fraction = 0
    function automatic is_inf64(input [63:0] x);
        begin is_inf64 = (x[62:52] == 11'h7ff) && (x[51:0] == 0); end
    endfunction

    // 0: exponent = 0 and fraction = 0
    function automatic is_zero64(input [63:0] x);
        begin is_zero64 = (x[62:52] == 0) && (x[51:0] == 0); end
    endfunction

    // Right shift a 56-bit value, but preserve whether any shifted-out bit was 1
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
                // If shifting away everything, result is 0 or sticky-only 1 
                shr_sticky56 = (x != 0) ? 56'd1 : 56'd0;
            end else begin
                tmp = x >> sh;
                sticky = 1'b0;

                // OR together all bits that were shifted out 
                for (i = 0; i < sh; i = i + 1)
                    sticky = sticky | x[i];

                // Put sticky info into bit 0 
                tmp[0] = tmp[0] | sticky;
                shr_sticky56 = tmp;
            end
        end
    endfunction

    function automatic [63:0] pack;
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

            // If exponent is too small for a normal number, shift right into
            // the subnormal range while preserving sticky information 
            if ((exp_r < -1022) || ((exp_r == -1022) && (ext_r[55] == 1'b0))) begin
                sh = -1022 - exp_r;
                if (sh < 0) sh = 0;
                ext_r = shr_sticky56(ext_r, sh);
                exp_r = -1022;
            end

            // Split extended significand into: main significand bits + guard, round, sticky
            sig_main = ext_r[55:3];
            guard    = ext_r[2];
            roundb   = ext_r[1];
            sticky   = ext_r[0];

            // Round-to-nearest-even: increment if guard=1 and any lower info says "round up"
            inc = guard && (roundb || sticky || sig_main[0]);
            sig_round = {1'b0, sig_main} + inc;

            // Exact zero result 
            if (sig_round == 0) begin
                pack = 64'd0;

            // Rounding overflowed so shift right once and increase exponent
            end else if (sig_round[53]) begin
                sig_round = sig_round >> 1;
                exp_r = exp_r + 1;

                // Overflow after rounding -> infinity
                if (exp_r + 1023 >= 2047)
                    pack = {sign, 11'h7ff, 52'd0};
                else
                    pack = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};

            // Subnormal result: exponent field is 0 and leading hidden 1 is absent
            end else if ((exp_r == -1022) && (sig_round[52] == 1'b0)) begin
                pack = {sign, 11'd0, sig_round[51:0]};

            // Normal overflow -> infinity
            end else if (exp_r + 1023 >= 2047) begin
                pack = {sign, 11'h7ff, 52'd0};

            // Normal finite result
            end else begin
                pack = {sign, exp_r[10:0] + 11'd1023, sig_round[51:0]};
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
            // x - y = x + (-y)
            y2 = sub ? {~y[63], y[62:0]} : y;

            // NaN
            if (is_nan64(x) || is_nan64(y2)) begin
                fp_addsub64 = QUIET_NAN;

            // inf + (-inf) = NaN
            end else if (is_inf64(x) && is_inf64(y2) && (x[63] != y2[63])) begin
                fp_addsub64 = QUIET_NAN;

            // Infinity + ... = Infinity
            end else if (is_inf64(x)) begin
                fp_addsub64 = x;
            end else if (is_inf64(y2)) begin
                fp_addsub64 = y2;

            // +0 + (-0) = 0
            end else if (is_zero64(x) && is_zero64(y2)) begin
                fp_addsub64 = 64'd0;
            end else begin
                // Extract fields
                sx = x[63]; sy = y2[63];
                ex = x[62:52]; ey = y2[62:52];
                fx = x[51:0]; fy = y2[51:0];

                // Remove bias
                // Subnormals use exponent -1022
                e1 = (ex == 0) ? -1022 : (ex - 1023);
                e2 = (ey == 0) ? -1022 : (ey - 1023);

                // Build significands
                // Normals = leading 1, Subnormals = leading 0
                mx = (ex == 0) ? {1'b0, fx} : {1'b1, fx};
                my = (ey == 0) ? {1'b0, fy} : {1'b1, fy};

                // Choose the operand with larger magnitude
                if ((e1 > e2) || ((e1 == e2) && (mx >= my))) begin
                    e_big   = e1; m_big = mx; s_big = sx;
                    e_small = e2; m_small = my; s_small = sy;
                end else begin
                    e_big   = e2; m_big = my; s_big = sy;
                    e_small = e1; m_small = mx; s_small = sx;
                end

                // Extend significands with guard/round/sticky bits
                er = e_big;
                ex_big = {m_big, 3'b000};

                // Shift smaller operand right to align exponents
                sh = e_big - e_small;
                ex_small = shr_sticky56({m_small, 3'b000}, sh);

                // Same sign => add magnitudes
                if (s_big == s_small) begin
                    sum57 = {1'b0, ex_big} + {1'b0, ex_small};
                    sr = s_big;

                    // If addition overflowed one bit, renormalize right by 1
                    if (sum57[56]) begin
                        ex_res = sum57[56:1];
                        ex_res[0] = ex_res[0] | sum57[0];
                        er = er + 1;
                    end else begin
                        ex_res = sum57[55:0];
                    end

                // Different signs => subtract smaller magnitude from larger
                end else begin
                    ex_res = ex_big - ex_small;
                    sr = s_big;

                    // Exact cancellation -> +0
                    if (ex_res == 0) begin
                        fp_addsub64 = 64'd0;
                    end

                    // Normalize left after subtraction
                    while ((ex_res[55] == 1'b0) && (er > -1022)) begin
                        ex_res = ex_res << 1;
                        er = er - 1;
                    end
                end

                // Final rounding + packing
                fp_addsub64 = pack(sr, er, ex_res);
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

            // inf * 0 is invalid
            end else if ((is_inf64(x) && is_zero64(y)) || (is_inf64(y) && is_zero64(x))) begin
                fp_mul64 = QUIET_NAN;

            // inf * sign
            end else if (is_inf64(x) || is_inf64(y)) begin
                fp_mul64 = {x[63]^y[63], 11'h7ff, 52'd0};

            // 0 * sign
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

                // Product of two normalized significands (1... * 1...) is in [1,4)
                // so there are two normalization cases
                if (prod[105]) begin
                    ext = {prod[105:53], prod[52], prod[51], |prod[50:0]};
                    er = er + 1;
                end else begin
                    ext = {prod[104:52], prod[51], prod[50], |prod[49:0]};
                end

                fp_mul64 = pack(sr, er, ext);
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

            // inf/inf and 0/0 are invalid
            end else if ((is_inf64(x) && is_inf64(y)) || (is_zero64(x) && is_zero64(y))) begin
                fp_div64 = QUIET_NAN;

            // inf / finite = inf
            end else if (is_inf64(x)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};

            // finite / inf = 0
            end else if (is_inf64(y)) begin
                fp_div64 = {x[63]^y[63], 63'd0};

            // finite / 0 = inf
            end else if (is_zero64(y)) begin
                fp_div64 = {x[63]^y[63], 11'h7ff, 52'd0};

            // 0 / finite = 0
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

                // Shift numerator to preserve fractional precision
                num = {mx, 55'd0};
                q = num / my;
                rem = num % my;

                // Normalize quotient if needed
                if (q[55] == 1'b0) begin
                    q = q << 1;
                    er = er - 1;
                end

                // Any nonzero remainder contributes to sticky
                q[0] = q[0] | (rem != 0);

                fp_div64 = pack (sr, er, q);
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