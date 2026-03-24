`timescale 1ns / 1ps
//
// fp_sqrt.v — FSQRT.D  IEEE 754 double-precision square root
// Restoring square root, 1 bit per cycle (55 iterations).
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
    reg [56:0]        remainder;    // partial remainder (57 bits: enough for trial = {root, 01} up to 57 bits)
    reg [54:0]        root;         // accumulated root bits (55 bits)
    reg [109:0]       radicand;     // 110-bit radicand, shifted out 2 bits/cycle
    reg [5:0]         iter_count;   // iteration counter

    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // -----------------------------------------------------------------
    // Rounding function (shared logic)
    // -----------------------------------------------------------------
    `include "fp_round_func.vh"

    // -----------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------
    localparam S_IDLE    = 2'd0;
    localparam S_SETUP   = 2'd1;
    localparam S_ITERATE = 2'd2;
    localparam S_FINISH  = 2'd3;
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
            root       <= 55'b0;
            remainder  <= 57'b0;
            radicand   <= 110'b0;
        end else begin
            done <= 1'b0;

            case (state)
                // =====================================================
                // IDLE: Wait for start, unpack and classify
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

                        busy  <= 1'b1;
                        state <= S_SETUP;
                    end
                end

                // =====================================================
                // SETUP: Handle special cases, prepare radicand
                // =====================================================
                S_SETUP: begin
                    special_case   <= 1'b0;
                    special_result <= 64'b0;
                    special_flags  <= 5'b0;
                    remainder      <= 57'b0;
                    root           <= 55'b0;

                    if (a_is_nan_r) begin
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        if (a_is_snan_r) special_flags[NV] <= 1'b1;
                        state <= S_FINISH;
                    end else if (a_sign_r && !a_is_zero_r) begin
                        special_case      <= 1'b1;
                        special_result    <= CANON_NAN;
                        special_flags[NV] <= 1'b1;
                        state <= S_FINISH;
                    end else if (a_is_inf_r) begin
                        special_case   <= 1'b1;
                        special_result <= {1'b0, EXP_MAX, 52'b0};
                        state <= S_FINISH;
                    end else if (a_is_zero_r) begin
                        special_case   <= 1'b1;
                        special_result <= {a_sign_r, 63'b0};
                        state <= S_FINISH;
                    end else begin
                        // Normal/subnormal: prepare radicand and result exponent
                        begin : prep_blk
                            reg [10:0] eff_exp;
                            reg        true_exp_odd;

                            eff_exp = a_is_sub_r ? 11'd1 : a_exp_r;

                            // true exponent = eff_exp - 1023
                            // true_exp is odd when eff_exp is even (since 1023 is odd)
                            true_exp_odd = ~eff_exp[0];

                            if (true_exp_odd) begin
                                // True exponent is odd: multiply significand by 2
                                // Radicand S = 2 * m, in [2, 4)
                                // 110-bit radicand: {m[52:0], 57'b0}
                                // where m[52] is the implicit 1, so top bits are 1x...
                                // Binary point conceptually after bit 108
                                // Top 2 bits [109:108] = {m[52], m[51]} = 1x
                                radicand <= {a_mant_r, 57'b0};

                                // Result biased exponent:
                                // result_true_exp = (true_exp - 1) / 2  (make it even first)
                                // result_biased = result_true_exp + 1023
                                //               = (eff_exp - 1024) / 2 + 1023
                                //               = eff_exp/2 - 512 + 1023
                                //               = eff_exp/2 + 511
                                // eff_exp is even, so eff_exp/2 = eff_exp >> 1
                                res_exp <= {2'b0, eff_exp[10:1]} + 13'sd511;
                            end else begin
                                // True exponent is even: significand as-is
                                // Radicand S = m, in [1, 2)
                                // 110-bit radicand: {2'b01, m[51:0], 56'b0}
                                // Top 2 bits [109:108] = 01
                                radicand <= {2'b01, a_mant_r[51:0], 56'b0};

                                // Result biased exponent:
                                // result_true_exp = true_exp / 2
                                // result_biased = (eff_exp - 1023) / 2 + 1023
                                // eff_exp is odd, so (eff_exp - 1023) is even
                                // = (eff_exp - 1023) / 2 + 1023
                                // = (eff_exp - 1) / 2 - 511 + 1023
                                // = (eff_exp - 1) / 2 + 512
                                // eff_exp is odd, (eff_exp-1) is even, (eff_exp-1)/2 = eff_exp >> 1
                                res_exp <= {2'b0, eff_exp[10:1]} + 13'sd512;
                            end
                        end
                        iter_count <= 6'd55;  // 55 iterations
                        state      <= S_ITERATE;
                    end
                end

                // =====================================================
                // ITERATE: Restoring square root, 1 bit per cycle
                // =====================================================
                S_ITERATE: begin
                    begin : iter_blk
                        reg [56:0] new_remainder;
                        reg [56:0] trial;

                        // Shift remainder left by 2, bring in top 2 bits of radicand
                        new_remainder = {remainder[54:0], radicand[109:108]};

                        // Trial value: 4*Q + 1 = {root, 2'b01}
                        // root is 55 bits, {root, 2'b01} = 57 bits
                        trial = {root, 2'b01};

                        if (new_remainder >= trial) begin
                            remainder <= new_remainder - trial;
                            root      <= {root[53:0], 1'b1};
                        end else begin
                            remainder <= new_remainder;
                            root      <= {root[53:0], 1'b0};
                        end

                        // Shift radicand left by 2
                        radicand <= {radicand[107:0], 2'b0};
                    end

                    if (iter_count == 6'd1)
                        state <= S_FINISH;
                    iter_count <= iter_count - 6'd1;
                end

                // =====================================================
                // FINISH: Normalize, round, pack result
                // =====================================================
                S_FINISH: begin
                    if (special_case) begin
                        result <= special_result;
                        flags  <= special_flags;
                    end else begin
                        begin : finish_blk
                            reg [54:0] q;
                            reg signed [12:0] exp_final;
                            reg [51:0] mant_final;
                            reg        g_bit, r_bit, s_bit;
                            reg        inexact;

                            // root[54:0] = 55 result bits
                            // root[54] = implicit 1 (should always be 1 for normal results)
                            // root[53:2] = 52 mantissa bits
                            // root[1] = guard bit
                            // root[0] = round bit
                            // remainder != 0 => sticky bit
                            q = root;
                            exp_final = res_exp;

                            // Normalize if needed (shouldn't be for normal inputs)
                            if (!q[54]) begin
                                q = q << 1;
                                exp_final = exp_final - 13'sd1;
                            end

                            mant_final = q[53:2];
                            g_bit      = q[1];
                            r_bit      = q[0];
                            s_bit      = (remainder != 57'b0);

                            inexact = g_bit | r_bit | s_bit;

                            // Rounding (use shared rounding function)
                            // sqrt result is always positive, so sign=0
                            if (fp_do_round(1'b0, g_bit, r_bit, s_bit, mant_final[0], rm)) begin
                                mant_final = mant_final + 52'd1;
                                if (mant_final == 52'd0)
                                    exp_final = exp_final + 13'sd1;
                            end

                            if (exp_final >= 13'sd2047) begin
                                result     <= {1'b0, EXP_MAX, 52'b0};
                                flags[OF]  <= 1'b1;
                                flags[NX]  <= 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[UF]  <= 1'b0;
                            end else if (exp_final <= 13'sd0) begin
                                result     <= 64'b0;
                                flags[UF]  <= 1'b1;
                                flags[NX]  <= 1'b1;
                                flags[NV]  <= 1'b0;
                                flags[DZ]  <= 1'b0;
                                flags[OF]  <= 1'b0;
                            end else begin
                                result     <= {1'b0, exp_final[10:0], mant_final};
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
