`timescale 1ns / 1ps
//
// fp_sqrt.v — FSQRT.D  IEEE 754 double-precision square root
// Non-restoring digit-recurrence, 1 bit per cycle (~55 cycles).
// Instantiates fp_round for final rounding.
//

module fp_sqrt (
    input         clk,
    input         rst,
    input         start,
    input  [63:0] a,
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
    // Unpacked operand (registered on start)
    // -----------------------------------------------------------------
    reg        a_sign_r;
    reg [10:0] a_exp_r;
    reg [52:0] a_mant_r;  // {implicit bit, frac[51:0]}

    reg a_is_nan_r, a_is_snan_r, a_is_inf_r, a_is_zero_r, a_is_sub_r;

    // -----------------------------------------------------------------
    // Iteration state
    // -----------------------------------------------------------------
    reg signed [12:0] res_exp;
    reg [113:0]       remainder;    // partial remainder, wide enough
    reg [56:0]        root;         // partial root (55 result bits + extras)
    reg [5:0]         iter_count;   // counts down from 55

    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // -----------------------------------------------------------------
    // Rounding
    // -----------------------------------------------------------------
    wire round_up;
    reg  r_guard, r_round, r_sticky, r_lsb, r_sign;
    reg  [2:0] r_rm;

    fp_round u_round (
        .sign      (r_sign),
        .guard     (r_guard),
        .round_bit (r_round),
        .sticky    (r_sticky),
        .lsb       (r_lsb),
        .rm        (r_rm),
        .round_up  (round_up)
    );

    // -----------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------
    localparam S_IDLE    = 2'd0;
    localparam S_ITERATE = 2'd1;
    localparam S_FINISH  = 2'd2;
    reg [1:0] state;

    // -----------------------------------------------------------------
    // Main sequential logic
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            result     <= 64'b0;
            flags      <= 5'b0;
            iter_count <= 6'd0;
            root       <= 57'b0;
            remainder  <= 114'b0;
        end else begin
            done <= 1'b0;

            case (state)
                // =====================================================
                // IDLE
                // =====================================================
                S_IDLE: begin
                    if (start) begin
                        // Unpack
                        a_sign_r <= a[63];
                        a_exp_r  <= a[62:52];
                        a_mant_r <= (a[62:52] == 11'b0) ? {1'b0, a[51:0]}
                                                        : {1'b1, a[51:0]};

                        a_is_nan_r  <= (a[62:52] == EXP_MAX) && (a[51:0] != 52'b0);
                        a_is_snan_r <= (a[62:52] == EXP_MAX) && (a[51:0] != 52'b0) && (a[51] == 1'b0);
                        a_is_inf_r  <= (a[62:52] == EXP_MAX) && (a[51:0] == 52'b0);
                        a_is_zero_r <= (a[62:52] == 11'b0)   && (a[51:0] == 52'b0);
                        a_is_sub_r  <= (a[62:52] == 11'b0)   && (a[51:0] != 52'b0);

                        busy       <= 1'b1;
                        state      <= S_ITERATE;
                        iter_count <= 6'd56;  // 56 = check specials; 55..1 = iterate
                        root       <= 57'b0;
                        remainder  <= 114'b0;
                    end
                end

                // =====================================================
                // ITERATE
                // =====================================================
                S_ITERATE: begin
                    if (iter_count == 6'd56) begin
                        // ---------------------------------------------------
                        // First cycle: special cases
                        // ---------------------------------------------------
                        special_case   <= 1'b0;
                        special_result <= 64'b0;
                        special_flags  <= 5'b0;

                        if (a_is_nan_r) begin
                            special_case   <= 1'b1;
                            special_result <= CANON_NAN;
                            if (a_is_snan_r) special_flags[NV] <= 1'b1;
                        end else if (a_sign_r && !a_is_zero_r) begin
                            // sqrt(negative) -> NaN, NV flag
                            special_case      <= 1'b1;
                            special_result    <= CANON_NAN;
                            special_flags[NV] <= 1'b1;
                        end else if (a_is_inf_r) begin
                            // sqrt(+Inf) -> +Inf
                            special_case   <= 1'b1;
                            special_result <= {1'b0, EXP_MAX, 52'b0};
                        end else if (a_is_zero_r) begin
                            // sqrt(+/-0) -> same zero
                            special_case   <= 1'b1;
                            special_result <= {a_sign_r, 63'b0};
                        end

                        if (a_is_nan_r || (a_sign_r && !a_is_zero_r) ||
                            a_is_inf_r || a_is_zero_r) begin
                            iter_count <= 6'd0;
                        end else begin
                            // Normal/subnormal: prepare for iteration
                            // Result exponent: floor((a_exp - 1023) / 2) + 1023
                            // If exp is odd, shift mantissa left by 1 to make it even
                            begin : prep_blk
                                reg [10:0] eff_exp;
                                reg [53:0] mant_shifted;

                                eff_exp = a_is_sub_r ? 11'd1 : a_exp_r;

                                if (eff_exp[0] == 1'b1) begin
                                    // Odd exponent: shift mantissa left by 1
                                    mant_shifted = {a_mant_r, 1'b0};
                                    res_exp <= $signed({2'b0, eff_exp} - 13'sd1) / 2 + $signed(13'sd1023);
                                end else begin
                                    // Even exponent
                                    mant_shifted = {1'b0, a_mant_r};
                                    res_exp <= $signed({2'b0, eff_exp}) / 2 + $signed(13'sd511);
                                end

                                // Load mantissa into upper bits of remainder
                                // We need to process 55 bits of result
                                remainder <= {mant_shifted, 60'b0};
                            end
                            iter_count <= 6'd55;
                        end
                    end else if (iter_count == 6'd0) begin
                        state <= S_FINISH;
                    end else begin
                        // ---------------------------------------------------
                        // Non-restoring square root iteration
                        // Trial: T = (2 * Q + 1) << (iter_count - 1)
                        // But simpler formulation:
                        //   R' = 4*R (shift left 2)... actually for radix-2
                        //   digit recurrence we bring in 2 bits of radicand
                        //   per iteration.
                        //
                        // Standard algorithm:
                        //   Each iteration produces 1 bit of result.
                        //   R = 2*R - (2*Q + 1) if R >= 0 after trial
                        //   else R = 2*R + (2*Q - 1), set bit = 0
                        //
                        // Simplified approach: bring in 2 bits at a time
                        // from the radicand, test and subtract.
                        // ---------------------------------------------------
                        begin : iter_blk
                            reg [113:0] trial;
                            // trial = 2*root + 1, shifted to align
                            trial = {root, 1'b1} << (iter_count - 6'd1);

                            if (remainder >= trial) begin
                                remainder <= remainder - trial;
                                root      <= {root[55:0], 1'b1};
                            end else begin
                                root <= {root[55:0], 1'b0};
                            end
                        end
                        iter_count <= iter_count - 6'd1;
                    end
                end

                // =====================================================
                // FINISH
                // =====================================================
                S_FINISH: begin
                    if (special_case) begin
                        result <= special_result;
                        flags  <= special_flags;
                    end else begin
                        begin : finish_blk
                            reg [55:0] q;
                            reg signed [12:0] exp_final;
                            reg [52:0] mant_final;
                            reg        g_bit, r_bit, s_bit;
                            reg [52:0] mant_rounded;
                            reg        inexact;

                            q = root[55:0];
                            exp_final = res_exp;

                            // root has 55 bits of result
                            // root[54] should be the implicit 1 for normalized results
                            // If not, normalize by shifting left
                            if (q[54] == 1'b0) begin
                                q = q << 1;
                                exp_final = exp_final - 13'sd1;
                            end

                            // Extract: q[54]=1(implicit), q[53:2]=52 mant bits,
                            //           q[1]=guard, q[0]=round, remainder=sticky
                            mant_final = {q[54], q[53:2]};
                            g_bit      = q[1];
                            r_bit      = q[0];
                            s_bit      = (remainder != 114'b0);

                            r_sign   = 1'b0;  // sqrt result always positive
                            r_guard  = g_bit;
                            r_round  = r_bit;
                            r_sticky = s_bit;
                            r_lsb    = q[2];
                            r_rm     = rm;

                            inexact = g_bit | r_bit | s_bit;

                            mant_rounded = mant_final + {52'b0, round_up};

                            // Check mantissa overflow from rounding
                            if (mant_rounded[52] && !mant_final[52]) begin
                                exp_final = exp_final + 13'sd1;
                            end

                            // Handle overflow (very unlikely for sqrt)
                            if (exp_final >= 13'sd2047) begin
                                result     <= {1'b0, EXP_MAX, 52'b0};
                                flags[OF]  <= 1'b1;
                                flags[NX]  <= 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[UF]  <= 1'b0;
                            end else if (exp_final <= 13'sd0) begin
                                // Underflow — flush to zero
                                result     <= 64'b0;
                                flags[UF]  <= 1'b1;
                                flags[NX]  <= 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[OF]  <= 1'b0;
                            end else begin
                                result     <= {1'b0, exp_final[10:0], mant_rounded[51:0]};
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
