// ============================================================================
// fp_add.v — IEEE 754 Double-Precision Floating-Point Adder/Subtractor
// FADD.D / FSUB.D for RV64IFD
// 3-cycle pipelined state machine (IDLE -> STAGE1 -> STAGE2 -> STAGE3)
// Vivado 2020.2 targeting 7-series FPGAs
// ============================================================================

module fp_add (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,       // pulse to begin operation
    input  wire        is_sub,      // 1 = FSUB.D, 0 = FADD.D
    input  wire [63:0] a,           // IEEE 754 operand A
    input  wire [63:0] b,           // IEEE 754 operand B
    input  wire [2:0]  rm,          // rounding mode (RNE/RTZ/RDN/RUP/RMM)
    output reg  [63:0] result,      // IEEE 754 result
    output reg  [4:0]  flags,       // {NV, DZ, OF, UF, NX}
    output reg         done,        // pulses 1 cycle when result ready
    output reg         busy
);

    // ========================================================================
    // State encoding
    // ========================================================================
    localparam IDLE   = 2'd0;
    localparam STAGE1 = 2'd1;
    localparam STAGE2 = 2'd2;
    localparam STAGE3 = 2'd3;

    reg [1:0] state;

    // ========================================================================
    // Special-value classification constants
    // ========================================================================
    localparam EXP_INF  = 11'h7FF;
    localparam CANON_NAN = 64'h7FF8_0000_0000_0000;

    // ========================================================================
    // Stage 1 registers — unpacked operands and special-case results
    // ========================================================================
    reg        a_sign, b_sign;
    reg [10:0] a_exp,  b_exp;
    reg [52:0] a_mant, b_mant;          // 53 bits: {implicit_bit, stored_mantissa}
    reg        a_is_zero, b_is_zero;
    reg        a_is_inf,  b_is_inf;
    reg        a_is_nan,  b_is_nan;
    reg        a_is_snan, b_is_snan;
    reg        a_is_sub,  b_is_sub_norm; // subnormal flags

    reg        eff_sub;                   // effective subtraction?
    reg        swap;                      // 1 if we swap so op_large >= op_small
    reg [10:0] exp_diff;
    reg [10:0] res_exp;                   // working exponent (larger of the two)
    reg        res_sign;

    // Large/small operand mantissas after swap decision
    reg [52:0] mant_large, mant_small;

    // Special-case early-out
    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // ========================================================================
    // Stage 2 registers — alignment and addition
    // ========================================================================
    reg [54:0] sum_raw;        // 55-bit add/sub result (1 carry + 1 implicit + 53 mant)
    reg        sum_sign;
    reg [10:0] sum_exp;
    reg        guard_s2, round_s2, sticky_s2;
    reg        sum_is_zero;

    // ========================================================================
    // Stage 3 wires/regs — normalization, rounding, packing
    // ========================================================================

    // LZC instance wires
    wire [6:0]  lzc_count;
    wire        lzc_zero;
    reg  [63:0] lzc_input;

    // Rounding instance wires
    wire        round_up;
    reg         rnd_sign, rnd_guard, rnd_round, rnd_sticky, rnd_lsb;

    // ========================================================================
    // Instantiate leading-zero counter
    // ========================================================================
    fp_lzc u_lzc (
        .data  (lzc_input),
        .count (lzc_count),
        .zero  (lzc_zero)
    );

    // ========================================================================
    // Instantiate rounding module
    // ========================================================================
    fp_round u_round (
        .sign      (rnd_sign),
        .guard     (rnd_guard),
        .round_bit (rnd_round),
        .sticky    (rnd_sticky),
        .lsb       (rnd_lsb),
        .rm        (rm),
        .round_up  (round_up)
    );

    // ========================================================================
    // LZC input: combinational feed from sum_raw (zero-extended to 64 bits)
    // The LZC is used in STAGE3 but is purely combinational, so we drive it
    // from registered Stage 2 outputs.
    // ========================================================================
    always @(*) begin
        lzc_input = {sum_raw, 9'b0};  // place 55-bit value at MSBs of 64-bit word
    end

    // ========================================================================
    // Rounding inputs: combinational, driven in STAGE3 logic
    // (assigned in the sequential block via intermediate regs fed to the instance)
    // ========================================================================

    // ========================================================================
    // Alignment helper: right-shift with sticky collection
    // We need up to 55-bit right shift of a 53-bit mantissa, collecting
    // guard, round, and sticky bits.
    // ========================================================================
    reg [54:0] aligned_small;   // {0, 0, mant_small} after shift — 55 bits
    reg        align_guard, align_round, align_sticky;

    always @(*) begin
        // Default
        aligned_small = 55'd0;
        align_guard   = 1'b0;
        align_round   = 1'b0;
        align_sticky  = 1'b0;

        if (exp_diff == 11'd0) begin
            // No shift needed
            aligned_small = {2'b0, mant_small};
            align_guard   = 1'b0;
            align_round   = 1'b0;
            align_sticky  = 1'b0;
        end else if (exp_diff == 11'd1) begin
            aligned_small = {2'b0, mant_small} >> 1;
            align_guard   = mant_small[0];
            align_round   = 1'b0;
            align_sticky  = 1'b0;
        end else if (exp_diff == 11'd2) begin
            aligned_small = {2'b0, mant_small} >> 2;
            align_guard   = mant_small[1];
            align_round   = mant_small[0];
            align_sticky  = 1'b0;
        end else if (exp_diff <= 11'd55) begin
            // General case: shift by exp_diff, collect GRS
            // We work with {mant_small, 3'b000} = 56 bits, shift right by exp_diff
            // then extract the proper fields
            begin : shift_block
                reg [55:0] extended;  // 53 + 3 = 56 bits
                reg [55:0] shifted;
                reg [5:0]  shamt;
                integer    i;
                reg        stk;

                extended = {mant_small, 3'b000};
                shamt    = exp_diff[5:0];
                shifted  = extended >> shamt;

                // Sticky = OR of all bits shifted out below round position
                stk = 1'b0;
                for (i = 0; i < 56; i = i + 1) begin
                    if (i[5:0] < shamt)
                        stk = stk | extended[i];
                end

                aligned_small = shifted[55:3] >> 2;  // need to be more careful
                // Recalculate properly:
                // After shifting mant_small right by exp_diff:
                //   bits [52:0] of shifted mantissa go into aligned_small
                //   bit at position -1 (first shifted out) = guard
                //   bit at position -2 = round
                //   OR of all remaining = sticky
                aligned_small = {2'b0, mant_small} >> shamt;
                // Guard bit: the bit just below the LSB after shift
                // We can extract from the extended shift
                align_guard  = shifted[2];
                align_round  = shifted[1];
                align_sticky = shifted[0] | (stk & ~shifted[2] & ~shifted[1] & ~shifted[0]);
                // More correct sticky: OR of all bits below round position
                // stk already has all bits < shamt of extended, but we need
                // only those below position 1 (round). Simplify:
                align_sticky = 1'b0;
                for (i = 0; i < 56; i = i + 1) begin
                    if (i[5:0] < shamt && i < 3)
                        align_sticky = align_sticky | extended[i];
                end
                // That gets the sub-GR bits from the original. But we also
                // need bits shifted past from higher positions. Let's redo cleanly.
            end

            // ----- Clean re-derivation of GRS -----
            begin : grs_clean
                // Place mantissa in a wide register with 3 extra low bits for GRS
                reg [108:0] wide;   // way more than needed, but safe
                reg [108:0] wide_shifted;
                integer     j;
                reg         stk2;

                wide = {53'b0, mant_small, 3'b000};  // 109 bits, mant starts at bit 3
                wide_shifted = wide >> exp_diff;

                // After this shift, bits [55:3] hold the aligned mantissa,
                // bit 2 = guard, bit 1 = round, bit 0 = sticky-partial
                aligned_small = wide_shifted[55:3];   // 53 bits in [52:0], could be up to 55
                aligned_small = {2'b0, wide_shifted[55:3]};
                align_guard   = wide_shifted[2];
                align_round   = wide_shifted[1];

                // Sticky: OR of bit 0 from shifted value plus any bits that
                // were shifted completely out of the 109-bit window
                stk2 = wide_shifted[0];
                for (j = 0; j < 56; j = j + 1) begin
                    if (j < (exp_diff - 11'd3) && j < 53)
                        stk2 = stk2 | mant_small[j];
                end
                align_sticky = stk2;
            end
        end else begin
            // exp_diff > 55: entire small mantissa shifts to sticky
            aligned_small = 55'd0;
            align_guard   = 1'b0;
            align_round   = 1'b0;
            align_sticky  = |mant_small;
        end
    end

    // ========================================================================
    // Main state machine
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            result  <= 64'd0;
            flags   <= 5'd0;
            done    <= 1'b0;
            busy    <= 1'b0;

            // Clear all pipeline regs
            a_sign <= 0; b_sign <= 0;
            a_exp  <= 0; b_exp  <= 0;
            a_mant <= 0; b_mant <= 0;
            a_is_zero <= 0; b_is_zero <= 0;
            a_is_inf  <= 0; b_is_inf  <= 0;
            a_is_nan  <= 0; b_is_nan  <= 0;
            a_is_snan <= 0; b_is_snan <= 0;
            a_is_sub  <= 0; b_is_sub_norm <= 0;
            eff_sub <= 0; swap <= 0;
            exp_diff <= 0; res_exp <= 0; res_sign <= 0;
            mant_large <= 0; mant_small <= 0;
            special_case <= 0; special_result <= 0; special_flags <= 0;
            sum_raw <= 0; sum_sign <= 0; sum_exp <= 0;
            guard_s2 <= 0; round_s2 <= 0; sticky_s2 <= 0;
            sum_is_zero <= 0;
        end else begin
            // Default: done is a single-cycle pulse
            done <= 1'b0;

            case (state)
                // ============================================================
                // IDLE: Wait for start pulse
                // ============================================================
                IDLE: begin
                    if (start) begin
                        state <= STAGE1;
                        busy  <= 1'b1;
                        flags <= 5'd0;

                        // ====================================================
                        // STAGE 1: Unpack operands, classify, handle specials
                        // ====================================================

                        // --- Unpack A ---
                        a_sign <= a[63];
                        a_exp  <= a[62:52];
                        a_mant <= (a[62:52] == 11'd0) ? {1'b0, a[51:0]}   // subnormal: implicit 0
                                                       : {1'b1, a[51:0]};  // normal: implicit 1

                        // --- Unpack B (flip sign for SUB) ---
                        b_sign <= b[63] ^ is_sub;
                        b_exp  <= b[62:52];
                        b_mant <= (b[62:52] == 11'd0) ? {1'b0, b[51:0]}
                                                       : {1'b1, b[51:0]};

                        // --- Classify A ---
                        a_is_zero <= (a[62:52] == 11'd0) && (a[51:0] == 52'd0);
                        a_is_sub  <= (a[62:52] == 11'd0) && (a[51:0] != 52'd0);
                        a_is_inf  <= (a[62:52] == EXP_INF) && (a[51:0] == 52'd0);
                        a_is_nan  <= (a[62:52] == EXP_INF) && (a[51:0] != 52'd0);
                        a_is_snan <= (a[62:52] == EXP_INF) && (a[51:0] != 52'd0) && (a[51] == 1'b0);

                        // --- Classify B ---
                        b_is_zero <= (b[62:52] == 11'd0) && (b[51:0] == 52'd0);
                        b_is_sub_norm <= (b[62:52] == 11'd0) && (b[51:0] != 52'd0);
                        b_is_inf  <= (b[62:52] == EXP_INF) && (b[51:0] == 52'd0);
                        b_is_nan  <= (b[62:52] == EXP_INF) && (b[51:0] != 52'd0);
                        b_is_snan <= (b[62:52] == EXP_INF) && (b[51:0] != 52'd0) && (b[51] == 1'b0);
                    end
                end

                // ============================================================
                // STAGE1 -> STAGE2 transition: resolve specials, compute swap
                // ============================================================
                STAGE1: begin
                    // Effective subtraction: signs differ
                    eff_sub <= a_sign ^ b_sign;

                    // --- Special case handling ---
                    // Priority: NaN > Inf > Zero
                    if (a_is_nan || b_is_nan) begin
                        // Any NaN input -> canonical NaN; NV if sNaN
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= {(a_is_snan | b_is_snan), 4'b0000};  // NV
                    end else if (a_is_inf && b_is_inf) begin
                        if (a_sign == b_sign) begin
                            // Inf + Inf (same sign) = Inf
                            special_case   <= 1'b1;
                            special_result <= {a_sign, 11'h7FF, 52'd0};
                            special_flags  <= 5'b00000;
                        end else begin
                            // Inf - Inf = NaN, NV flag
                            special_case   <= 1'b1;
                            special_result <= CANON_NAN;
                            special_flags  <= 5'b10000;  // NV
                        end
                    end else if (a_is_inf) begin
                        special_case   <= 1'b1;
                        special_result <= {a_sign, 11'h7FF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if (b_is_inf) begin
                        special_case   <= 1'b1;
                        special_result <= {b_sign, 11'h7FF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if (a_is_zero && b_is_zero) begin
                        // +0 + -0 = +0 (except in RDN mode -> -0)
                        special_case   <= 1'b1;
                        if (a_sign == b_sign)
                            special_result <= {a_sign, 63'd0};
                        else
                            special_result <= (rm == 3'b010) ? {1'b1, 63'd0} : 64'd0; // RDN -> -0
                        special_flags  <= 5'b00000;
                    end else if (a_is_zero) begin
                        // 0 + B = B
                        special_case   <= 1'b1;
                        special_result <= {b_sign, b_exp, b_mant[51:0]};
                        special_flags  <= 5'b00000;
                    end else if (b_is_zero) begin
                        // A + 0 = A
                        special_case   <= 1'b1;
                        special_result <= {a_sign, a_exp, a_mant[51:0]};
                        special_flags  <= 5'b00000;
                    end else begin
                        special_case <= 1'b0;
                    end

                    // --- Determine larger operand for alignment ---
                    // Compare by (exponent, mantissa) to decide swap
                    if (a_exp > b_exp || (a_exp == b_exp && a_mant >= b_mant)) begin
                        swap       <= 1'b0;
                        mant_large <= a_mant;
                        mant_small <= b_mant;
                        res_exp    <= a_exp;
                        res_sign   <= a_sign;
                        exp_diff   <= a_exp - b_exp;
                    end else begin
                        swap       <= 1'b1;
                        mant_large <= b_mant;
                        mant_small <= a_mant;
                        res_exp    <= b_exp;
                        res_sign   <= b_sign;
                        exp_diff   <= b_exp - a_exp;
                    end

                    state <= STAGE2;
                end

                // ============================================================
                // STAGE2: Alignment and addition/subtraction
                // ============================================================
                STAGE2: begin
                    if (special_case) begin
                        // Early-out: skip to result delivery
                        result <= special_result;
                        flags  <= special_flags;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= IDLE;
                    end else begin
                        // Perform aligned addition or subtraction
                        // aligned_small, align_guard/round/sticky come from
                        // the combinational alignment block above

                        if (!(a_sign ^ b_sign)) begin
                            // Effective addition: same signs
                            sum_raw <= {2'b0, mant_large} + aligned_small;
                            sum_sign <= res_sign;
                        end else begin
                            // Effective subtraction: different signs
                            // Since mant_large >= mant_small, result is non-negative
                            sum_raw  <= {2'b0, mant_large} - aligned_small;
                            sum_sign <= res_sign;
                        end

                        sum_exp   <= res_exp;
                        guard_s2  <= align_guard;
                        round_s2  <= align_round;
                        sticky_s2 <= align_sticky;

                        // Detect zero result (will be confirmed in STAGE3 after
                        // normalization, but a quick check helps)
                        sum_is_zero <= ({2'b0, mant_large} == aligned_small) &&
                                       !align_guard && !align_round && !align_sticky &&
                                       (a_sign ^ b_sign);

                        state <= STAGE3;
                    end
                end

                // ============================================================
                // STAGE3: Normalize, round, detect overflow/underflow, pack
                // ============================================================
                STAGE3: begin
                    begin : stage3_block
                        reg [54:0] norm_mant;
                        reg [10:0] norm_exp;
                        reg [6:0]  shift_amt;
                        reg        s3_guard, s3_round, s3_sticky;
                        reg [51:0] final_mant;
                        reg [10:0] final_exp;
                        reg        final_sign;
                        reg [4:0]  final_flags;
                        reg        overflow, underflow;

                        final_flags = 5'd0;
                        overflow    = 1'b0;
                        underflow   = 1'b0;

                        if (sum_is_zero) begin
                            // Result is exactly zero
                            // Sign: +0 unless rounding mode is RDN -> -0
                            final_sign = (rm == 3'b010) ? 1'b1 : 1'b0;
                            final_exp  = 11'd0;
                            final_mant = 52'd0;
                            s3_guard   = 1'b0;
                            s3_round   = 1'b0;
                            s3_sticky  = 1'b0;
                        end else begin
                            final_sign = sum_sign;

                            // --- Normalization ---
                            // sum_raw is 55 bits. Normal result has the leading 1
                            // somewhere in bits [54:0].
                            if (sum_raw[54]) begin
                                // Carry-out from addition: shift right by 1
                                norm_mant  = sum_raw >> 1;
                                norm_exp   = sum_exp + 11'd1;
                                // The bit shifted out becomes guard; old guard->round; etc.
                                s3_guard   = sum_raw[0];
                                s3_round   = guard_s2;
                                s3_sticky  = round_s2 | sticky_s2;
                            end else if (sum_raw[53]) begin
                                // Already normalized (leading 1 in bit 53)
                                norm_mant  = sum_raw;
                                norm_exp   = sum_exp;
                                s3_guard   = guard_s2;
                                s3_round   = round_s2;
                                s3_sticky  = sticky_s2;
                            end else begin
                                // Need to left-shift to normalize (subtraction case)
                                // Use LZC to find how far to shift
                                // lzc_input is driven combinationally from sum_raw
                                // lzc_count gives the number of leading zeros in the
                                // 64-bit value {sum_raw, 9'b0}
                                // Since sum_raw is in bits [63:9] of lzc_input,
                                // and bit 54 of sum_raw maps to bit 63 of lzc_input,
                                // the count tells us leading zeros from the MSB.
                                // For a 55-bit value starting at bit 54, if lzc says N,
                                // we need to shift left by N to place leading 1 at bit 54.
                                // But we actually want leading 1 at bit 53 (the implicit bit
                                // position). So shift_amt = lzc_count - 1 if sum_raw occupies
                                // bits [63:9]. Actually let's think about it:
                                // lzc_input = {sum_raw, 9'b0}, so bit 63..9 = sum_raw[54..0]
                                // If sum_raw[53] is the target position, and the leading 1 is
                                // at position (63 - lzc_count) in lzc_input, which maps to
                                // sum_raw position (63 - lzc_count - 9) = (54 - lzc_count).
                                // We want it at position 53 in sum_raw.
                                // shift_amt = 53 - (54 - lzc_count) = lzc_count - 1
                                // But lzc_count could be 0 if bit 63 is set (handled above).

                                if (lzc_count <= 7'd1) begin
                                    shift_amt = 7'd0;
                                end else begin
                                    shift_amt = lzc_count - 7'd1;
                                end

                                // Check if shift would make exponent go below 1
                                if (shift_amt >= sum_exp) begin
                                    // Result becomes subnormal
                                    // Shift only enough to reach exp = 0
                                    if (sum_exp > 11'd0) begin
                                        norm_mant = sum_raw << (sum_exp - 11'd1);
                                        norm_exp  = 11'd0;
                                    end else begin
                                        norm_mant = sum_raw;
                                        norm_exp  = 11'd0;
                                    end
                                    underflow = 1'b1;
                                end else begin
                                    norm_mant = sum_raw << shift_amt;
                                    norm_exp  = sum_exp - {4'd0, shift_amt};
                                end

                                // After left shift, guard/round/sticky may incorporate
                                // the original GRS bits (shifted in from the right)
                                // For simplicity, after a left-shift the old GRS bits
                                // get shifted into the mantissa LSBs, so we set GRS to
                                // what remains
                                s3_guard  = guard_s2;
                                s3_round  = round_s2;
                                s3_sticky = sticky_s2;
                            end

                            // --- Apply rounding ---
                            // Drive the rounding module inputs
                            rnd_sign   = final_sign;
                            rnd_guard  = s3_guard;
                            rnd_round  = s3_round;
                            rnd_sticky = s3_sticky;
                            rnd_lsb    = norm_mant[0];

                            // round_up comes from the combinational fp_round instance

                            // Add rounding increment
                            if (round_up) begin
                                {norm_exp, norm_mant} = {norm_exp, norm_mant} + 1;
                                // Check if rounding caused carry (mantissa overflow)
                                if (norm_mant[54]) begin
                                    norm_mant = norm_mant >> 1;
                                    norm_exp  = norm_exp + 11'd1;
                                end
                            end

                            // --- Overflow detection ---
                            if (norm_exp >= 11'h7FF) begin
                                overflow = 1'b1;
                                final_flags = final_flags | 5'b00101;  // OF + NX
                                // Overflow: result depends on rounding mode and sign
                                case (rm)
                                    3'b000: begin  // RNE: overflow -> Inf
                                        final_exp  = 11'h7FF;
                                        final_mant = 52'd0;
                                    end
                                    3'b001: begin  // RTZ: overflow -> largest finite
                                        final_exp  = 11'h7FE;
                                        final_mant = {52{1'b1}};
                                    end
                                    3'b010: begin  // RDN
                                        if (final_sign) begin
                                            final_exp  = 11'h7FF;
                                            final_mant = 52'd0;
                                        end else begin
                                            final_exp  = 11'h7FE;
                                            final_mant = {52{1'b1}};
                                        end
                                    end
                                    3'b011: begin  // RUP
                                        if (final_sign) begin
                                            final_exp  = 11'h7FE;
                                            final_mant = {52{1'b1}};
                                        end else begin
                                            final_exp  = 11'h7FF;
                                            final_mant = 52'd0;
                                        end
                                    end
                                    3'b100: begin  // RMM: overflow -> Inf
                                        final_exp  = 11'h7FF;
                                        final_mant = 52'd0;
                                    end
                                    default: begin
                                        final_exp  = 11'h7FF;
                                        final_mant = 52'd0;
                                    end
                                endcase
                            end else if (norm_exp == 11'd0) begin
                                // Subnormal result
                                final_exp  = 11'd0;
                                final_mant = norm_mant[51:0]; // no implicit bit stored
                                if (s3_guard | s3_round | s3_sticky) begin
                                    underflow   = 1'b1;
                                    final_flags = final_flags | 5'b00011;  // UF + NX
                                end
                            end else begin
                                // Normal result
                                final_exp  = norm_exp;
                                final_mant = norm_mant[51:0]; // drop implicit bit
                                if (s3_guard | s3_round | s3_sticky)
                                    final_flags = final_flags | 5'b00001;  // NX
                            end
                        end

                        // --- Pack result ---
                        result <= {final_sign, final_exp, final_mant};
                        flags  <= final_flags;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
