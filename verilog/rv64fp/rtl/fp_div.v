`timescale 1ns / 1ps
//
// fp_div.v — FDIV.D  IEEE 754 double-precision division
// Non-restoring radix-2 iterative divider, 1 bit per cycle (56 cycles).
// Instantiates fp_round for final rounding.
//

module fp_div (
    input         clk,
    input         rst,
    input         start,
    input  [63:0] a,       // dividend
    input  [63:0] b,       // divisor
    input  [2:0]  rm,
    output reg [63:0] result,
    output reg [4:0]  flags,
    output reg        done,
    output reg        busy
);

    // -----------------------------------------------------------------
    // IEEE 754 constants
    // -----------------------------------------------------------------
    localparam [63:0] CANON_NAN = 64'h7FF8_0000_0000_0000;
    localparam [10:0] EXP_MAX   = 11'h7FF;
    localparam [10:0] EXP_BIAS  = 11'd1023;

    // Flag bit positions: {NV, DZ, OF, UF, NX}
    localparam NV = 4, DZ = 3, OF = 2, UF = 1, NX = 0;

    // -----------------------------------------------------------------
    // Unpacked operand fields (registered on start)
    // -----------------------------------------------------------------
    reg        a_sign_r, b_sign_r;
    reg [10:0] a_exp_r,  b_exp_r;
    reg [52:0] a_mant_r, b_mant_r;  // {implicit_1/0, frac[51:0]}

    // Classification flags (registered on start)
    reg a_is_nan_r, b_is_nan_r;
    reg a_is_snan_r, b_is_snan_r;
    reg a_is_inf_r,  b_is_inf_r;
    reg a_is_zero_r, b_is_zero_r;
    reg a_is_sub_r,  b_is_sub_r;

    // Result sign
    reg res_sign_r;

    // -----------------------------------------------------------------
    // Iteration state
    // -----------------------------------------------------------------
    reg signed [12:0] res_exp;       // biased result exponent (signed for underflow)
    reg [56:0]        quotient;      // 57 bits: 1 integer + 52 mantissa + g + r + extra
    reg signed [56:0] partial_rem;   // partial remainder (signed)
    reg [54:0]        divisor_r;     // stored divisor mantissa (55 bits)
    reg [5:0]         iter_count;    // counts down from 56

    // Special-case early-out
    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // -----------------------------------------------------------------
    // Rounding function (shared logic)
    // -----------------------------------------------------------------
    `include "fp_round_func.vh"

    // -----------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------
    localparam S_IDLE     = 2'd0;
    localparam S_ITERATE  = 2'd1;
    localparam S_FINISH   = 2'd2;
    reg [1:0] state;

    // -----------------------------------------------------------------
    // Main sequential logic
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            result      <= 64'b0;
            flags       <= 5'b0;
            iter_count  <= 6'd0;
            quotient    <= 57'b0;
            partial_rem <= 57'sb0;
        end else begin
            done <= 1'b0;  // default: pulse for one cycle

            case (state)
                // =====================================================
                // IDLE — wait for start, unpack, detect special cases
                // =====================================================
                S_IDLE: begin
                    if (start) begin
                        // ---- Unpack a ----
                        a_sign_r <= a[63];
                        a_exp_r  <= a[62:52];
                        a_mant_r <= (a[62:52] == 11'b0) ? {1'b0, a[51:0]}
                                                        : {1'b1, a[51:0]};
                        // ---- Unpack b ----
                        b_sign_r <= b[63];
                        b_exp_r  <= b[62:52];
                        b_mant_r <= (b[62:52] == 11'b0) ? {1'b0, b[51:0]}
                                                        : {1'b1, b[51:0]};

                        // ---- Classify ----
                        a_is_nan_r  <= (a[62:52] == EXP_MAX) && (a[51:0] != 52'b0);
                        b_is_nan_r  <= (b[62:52] == EXP_MAX) && (b[51:0] != 52'b0);
                        a_is_snan_r <= (a[62:52] == EXP_MAX) && (a[51:0] != 52'b0) && (a[51] == 1'b0);
                        b_is_snan_r <= (b[62:52] == EXP_MAX) && (b[51:0] != 52'b0) && (b[51] == 1'b0);
                        a_is_inf_r  <= (a[62:52] == EXP_MAX) && (a[51:0] == 52'b0);
                        b_is_inf_r  <= (b[62:52] == EXP_MAX) && (b[51:0] == 52'b0);
                        a_is_zero_r <= (a[62:52] == 11'b0)   && (a[51:0] == 52'b0);
                        b_is_zero_r <= (b[62:52] == 11'b0)   && (b[51:0] == 52'b0);
                        a_is_sub_r  <= (a[62:52] == 11'b0)   && (a[51:0] != 52'b0);
                        b_is_sub_r  <= (b[62:52] == 11'b0)   && (b[51:0] != 52'b0);

                        res_sign_r <= a[63] ^ b[63];

                        // Start special-case detection next cycle via
                        // combinational signals sampled in S_IDLE.
                        // For now, go to iterate; we'll check specials
                        // in the first cycle of S_ITERATE.
                        busy       <= 1'b1;
                        state      <= S_ITERATE;
                        iter_count <= 6'd57;  // will check specials when count==57
                        quotient   <= 57'b0;
                        partial_rem <= 57'sb0;
                    end
                end

                // =====================================================
                // ITERATE — first cycle handles specials, then iterate
                // =====================================================
                S_ITERATE: begin
                    if (iter_count == 6'd57) begin
                        // ---------------------------------------------------
                        // First cycle after unpack: handle special cases
                        // ---------------------------------------------------
                        special_case   <= 1'b0;
                        special_result <= 64'b0;
                        special_flags  <= 5'b0;

                        if (a_is_nan_r || b_is_nan_r) begin
                            // Any NaN input -> canonical NaN
                            special_case   <= 1'b1;
                            special_result <= CANON_NAN;
                            if (a_is_snan_r || b_is_snan_r)
                                special_flags[NV] <= 1'b1;
                        end else if (a_is_inf_r && b_is_inf_r) begin
                            // Inf / Inf -> NaN (NV)
                            special_case      <= 1'b1;
                            special_result    <= CANON_NAN;
                            special_flags[NV] <= 1'b1;
                        end else if (a_is_zero_r && b_is_zero_r) begin
                            // 0 / 0 -> NaN (NV)
                            special_case      <= 1'b1;
                            special_result    <= CANON_NAN;
                            special_flags[NV] <= 1'b1;
                        end else if (a_is_inf_r) begin
                            // Inf / finite -> Inf
                            special_case   <= 1'b1;
                            special_result <= {res_sign_r, EXP_MAX, 52'b0};
                        end else if (b_is_zero_r) begin
                            // finite / 0 -> Inf (DZ)
                            special_case      <= 1'b1;
                            special_result    <= {res_sign_r, EXP_MAX, 52'b0};
                            special_flags[DZ] <= 1'b1;
                        end else if (a_is_zero_r || b_is_inf_r) begin
                            // 0 / finite -> 0, finite / Inf -> 0
                            special_case   <= 1'b1;
                            special_result <= {res_sign_r, 63'b0};
                        end

                        // If not special, set up for iteration
                        if (!(a_is_nan_r || b_is_nan_r ||
                              (a_is_inf_r && b_is_inf_r) ||
                              (a_is_zero_r && b_is_zero_r) ||
                              a_is_inf_r || b_is_zero_r ||
                              a_is_zero_r || b_is_inf_r)) begin
                            // Compute trial exponent (signed)
                            // For subnormals, effective exponent = 1 (not 0)
                            res_exp <= $signed({2'b0, (a_is_sub_r ? 11'd1 : a_exp_r)})
                                     - $signed({2'b0, (b_is_sub_r ? 11'd1 : b_exp_r)})
                                     + $signed(13'd1023);

                            // Setup for restoring division.
                            // Pre-subtract if a_mant >= b_mant to keep remainder < divisor.
                            divisor_r <= {2'b0, b_mant_r};
                            if (a_mant_r >= b_mant_r) begin
                                // Quotient integer bit is 1
                                partial_rem <= {4'b0, a_mant_r - b_mant_r};
                                quotient    <= {56'b0, 1'b1};  // set bit 0 initially
                            end else begin
                                // Quotient < 1: adjust exponent
                                partial_rem <= {4'b0, a_mant_r};
                                quotient    <= 57'b0;
                                res_exp <= $signed({2'b0, (a_is_sub_r ? 11'd1 : a_exp_r)})
                                         - $signed({2'b0, (b_is_sub_r ? 11'd1 : b_exp_r)})
                                         + $signed(13'd1022); // BIAS-1 for quotient in (0.5,1)
                            end
                            iter_count <= 6'd55;  // 55 more iterations for remaining bits
                        end else begin
                            // Special case: jump to finish
                            iter_count <= 6'd0;
                        end
                    end else if (iter_count == 6'd0) begin
                        // Done iterating (or special case)
                        state <= S_FINISH;
                    end else begin
                        // ---------------------------------------------------
                        // Restoring division step (produces binary quotient directly)
                        // ---------------------------------------------------
                        begin : div_step
                            reg signed [56:0] trial;
                            trial = (partial_rem <<< 1) - $signed({2'b0, divisor_r});
                            if (trial[56] == 1'b0) begin
                                // Trial subtraction succeeded (non-negative)
                                quotient    <= {quotient[55:0], 1'b1};
                                partial_rem <= trial;
                            end else begin
                                // Trial subtraction produced negative: restore (don't subtract)
                                quotient    <= {quotient[55:0], 1'b0};
                                partial_rem <= partial_rem <<< 1;  // just shift, no subtract
                            end
                        end
                        iter_count <= iter_count - 6'd1;
                    end
                end

                // =====================================================
                // FINISH — normalize, round, pack
                // =====================================================
                S_FINISH: begin
                    if (special_case) begin
                        result <= special_result;
                        flags  <= special_flags;
                    end else begin
                        // Convert non-restoring quotient to standard binary:
                        // Replace 0-digits (which mean -1) by restoring.
                        // The quotient from non-restoring is already in
                        // a form where bit=1 means +1 and bit=0 means -1.
                        // Final quotient = quotient (as generated) after
                        // correction: if final remainder < 0, subtract 1
                        // from quotient and add divisor to remainder.
                        begin : finish_blk
                            reg [56:0] q_final;
                            reg [56:0] rem_final;
                            reg signed [12:0] exp_final;
                            reg [52:0] mant_final;  // 1.52
                            reg        g_bit, r_bit, s_bit;
                            reg [52:0] mant_rounded;
                            reg        inexact;

                            // Restoring division produces binary quotient directly.
                            // Remainder is always non-negative.
                            q_final   = quotient;
                            rem_final = partial_rem;

                            // q_final has 56 significant bits.
                            // Format: bit[55] is the integer bit (should be 1 for normalized).
                            // If bit[55]==0, shift left by 1 and decrement exponent.
                            exp_final = res_exp;
                            if (q_final[55] == 1'b0) begin
                                q_final   = q_final << 1;
                                exp_final = exp_final - 13'sd1;
                            end

                            // Extract mantissa (52 bits), guard, round, sticky
                            // q_final[55] = implicit 1
                            // q_final[54:3] = 52 mantissa bits
                            // q_final[2]   = guard
                            // q_final[1]   = round
                            // q_final[0] | (rem_final != 0) = sticky
                            mant_final = {q_final[55], q_final[54:3]};
                            g_bit      = q_final[2];
                            r_bit      = q_final[1];
                            s_bit      = q_final[0] | (rem_final != 57'b0);

                            inexact = g_bit | r_bit | s_bit;

                            // Apply rounding (use shared rounding function)
                            begin : div_round_apply
                                reg do_rnd;
                                do_rnd = fp_do_round(res_sign_r, g_bit, r_bit, s_bit, q_final[3], rm);
                                mant_rounded = mant_final + {52'b0, do_rnd};

                                if (mant_rounded[52] && !mant_final[52]) begin
                                    exp_final = exp_final + 13'sd1;
                                end else if (mant_rounded == 53'b0 && do_rnd) begin
                                    exp_final = exp_final + 13'sd1;
                                    mant_rounded = 53'h10_0000_0000_0000;
                                end
                            end

                            // Handle overflow
                            if (exp_final >= 13'sd2047) begin
                                // Overflow to infinity
                                result     <= {res_sign_r, EXP_MAX, 52'b0};
                                flags[OF]  <= 1'b1;
                                flags[NX]  <= 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[UF]  <= 1'b0;
                            end else if (exp_final <= 13'sd0) begin
                                // Underflow — flush to zero for simplicity
                                // (Full subnormal support would shift right by 1-exp_final)
                                result     <= {res_sign_r, 63'b0};
                                flags[UF]  <= 1'b1;
                                flags[NX]  <= inexact | 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[OF]  <= 1'b0;
                            end else begin
                                // Normal result
                                result     <= {res_sign_r, exp_final[10:0], mant_rounded[51:0]};
                                flags[NX]  <= inexact;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[OF]  <= 1'b0;
                                flags[UF]  <= 1'b0;
                            end
                        end
                    end
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
