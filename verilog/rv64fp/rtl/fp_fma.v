// ============================================================================
// fp_fma.v — IEEE 754 Double-Precision Fused Multiply-Add
// FMADD.D / FMSUB.D / FNMSUB.D / FNMADD.D for RV64IFD
// 4-cycle pipelined state machine (IDLE -> S1 -> S2 -> S3 -> S4)
// Vivado 2020.2 targeting 7-series FPGAs (~500 LUTs + DSP48E1 slices)
//
// RISC-V FMA operations:
//   FMADD  (op=00):  +(a*b) + c
//   FMSUB  (op=01):  +(a*b) - c
//   FNMSUB (op=10):  -(a*b) + c
//   FNMADD (op=11):  -(a*b) - c
// ============================================================================

module fp_fma (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,       // pulse to begin operation
    input  wire [1:0]  op,          // 00=FMADD, 01=FMSUB, 10=FNMSUB, 11=FNMADD
    input  wire [63:0] a,           // multiplicand
    input  wire [63:0] b,           // multiplier
    input  wire [63:0] c,           // addend
    input  wire [2:0]  rm,          // rounding mode
    output reg  [63:0] result,      // IEEE 754 result
    output reg  [4:0]  flags,       // {NV, DZ, OF, UF, NX}
    output reg         done,        // pulses 1 cycle when result ready
    output reg         busy
);

    // ========================================================================
    // State encoding
    // ========================================================================
    localparam IDLE = 3'd0;
    localparam S1   = 3'd1;
    localparam S2   = 3'd2;
    localparam S3   = 3'd3;
    localparam S4   = 3'd4;

    reg [2:0] state;

    // ========================================================================
    // Constants
    // ========================================================================
    localparam EXP_INF   = 11'h7FF;
    localparam BIAS      = 11'd1023;
    localparam CANON_NAN = 64'h7FF8_0000_0000_0000;

    // ========================================================================
    // Stage 1 registers — unpack and classify
    // ========================================================================
    reg        a_sign, b_sign, c_sign;
    reg [10:0] a_exp, b_exp, c_exp;
    reg [52:0] a_mant, b_mant, c_mant;    // 53 bits each

    reg        a_is_zero, b_is_zero, c_is_zero;
    reg        a_is_inf,  b_is_inf,  c_is_inf;
    reg        a_is_nan,  b_is_nan,  c_is_nan;
    reg        a_is_snan, b_is_snan, c_is_snan;
    reg        a_is_sub,  b_is_sub,  c_is_sub;

    reg        prod_sign;      // sign of the product a*b (after op modification)
    reg        add_sign;       // sign of the addend c (after op modification)
    reg        negate_prod;    // negate the product (FNMSUB, FNMADD)
    reg        negate_c;       // negate the addend (FMSUB, FNMADD)

    // Special case early-out
    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // ========================================================================
    // Stage 2 registers — multiply and align
    // ========================================================================
    reg [105:0]        product;             // 53x53 = 106-bit product
    reg signed [12:0]  prod_exp;            // product exponent (signed)
    reg signed [12:0]  c_exp_ext;           // addend exponent (signed, extended)
    reg                eff_sub;             // effective subtraction (product vs addend)

    // Aligned addend: the addend must be aligned to the product.
    // Product is 106 bits wide (positions 105..0).
    // We need extra bits for carry and for sticky accumulation.
    // Use 162-bit alignment register: 106 product bits + 3 GRS + margin
    reg [161:0]        aligned_c;
    reg                align_sticky;        // sticky from bits shifted out of aligned_c
    reg signed [12:0]  result_exp;          // exponent of the wider operand

    // ========================================================================
    // Stage 3 registers — addition
    // ========================================================================
    reg [161:0]        sum_raw;             // result of addition/subtraction
    reg                sum_sign;
    reg signed [12:0]  sum_exp;
    reg                sum_sticky;

    // ========================================================================
    // Stage 4 — normalization, rounding, packing
    // ========================================================================

    // LZC instance
    reg  [63:0] lzc_input;
    wire [6:0]  lzc_count;
    wire        lzc_zero;

    fp_lzc u_lzc (
        .data  (lzc_input),
        .count (lzc_count),
        .zero  (lzc_zero)
    );

    // Rounding instance
    reg  rnd_sign, rnd_guard, rnd_round, rnd_sticky, rnd_lsb;
    wire round_up;

    fp_round u_round (
        .sign      (rnd_sign),
        .guard     (rnd_guard),
        .round_bit (rnd_round),
        .sticky    (rnd_sticky),
        .lsb       (rnd_lsb),
        .rm        (rm),
        .round_up  (round_up)
    );

    // LZC input driver: combinational from sum_raw MSBs
    always @(*) begin
        lzc_input = sum_raw[161:98];  // top 64 bits of the sum
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

            a_sign <= 0; b_sign <= 0; c_sign <= 0;
            a_exp <= 0; b_exp <= 0; c_exp <= 0;
            a_mant <= 0; b_mant <= 0; c_mant <= 0;
            a_is_zero <= 0; b_is_zero <= 0; c_is_zero <= 0;
            a_is_inf <= 0; b_is_inf <= 0; c_is_inf <= 0;
            a_is_nan <= 0; b_is_nan <= 0; c_is_nan <= 0;
            a_is_snan <= 0; b_is_snan <= 0; c_is_snan <= 0;
            a_is_sub <= 0; b_is_sub <= 0; c_is_sub <= 0;
            prod_sign <= 0; add_sign <= 0;
            negate_prod <= 0; negate_c <= 0;
            special_case <= 0; special_result <= 0; special_flags <= 0;
            product <= 0; prod_exp <= 0; c_exp_ext <= 0;
            eff_sub <= 0; aligned_c <= 0; align_sticky <= 0;
            result_exp <= 0;
            sum_raw <= 0; sum_sign <= 0; sum_exp <= 0; sum_sticky <= 0;
        end else begin
            done <= 1'b0;

            case (state)
                // ============================================================
                // IDLE: Wait for start
                // ============================================================
                IDLE: begin
                    if (start) begin
                        state <= S1;
                        busy  <= 1'b1;
                        flags <= 5'd0;

                        // --- Decode operation ---
                        // op[1] negates the product, op[0] negates the addend
                        negate_prod <= op[1];
                        negate_c    <= op[0];

                        // --- Unpack A ---
                        a_sign <= a[63];
                        a_exp  <= a[62:52];
                        a_mant <= (a[62:52] == 11'd0) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};

                        // --- Unpack B ---
                        b_sign <= b[63];
                        b_exp  <= b[62:52];
                        b_mant <= (b[62:52] == 11'd0) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};

                        // --- Unpack C ---
                        c_sign <= c[63];
                        c_exp  <= c[62:52];
                        c_mant <= (c[62:52] == 11'd0) ? {1'b0, c[51:0]} : {1'b1, c[51:0]};

                        // --- Classify ---
                        a_is_zero <= (a[62:52] == 11'd0) && (a[51:0] == 52'd0);
                        a_is_sub  <= (a[62:52] == 11'd0) && (a[51:0] != 52'd0);
                        a_is_inf  <= (a[62:52] == EXP_INF) && (a[51:0] == 52'd0);
                        a_is_nan  <= (a[62:52] == EXP_INF) && (a[51:0] != 52'd0);
                        a_is_snan <= (a[62:52] == EXP_INF) && (a[51:0] != 52'd0) && (a[51] == 1'b0);

                        b_is_zero <= (b[62:52] == 11'd0) && (b[51:0] == 52'd0);
                        b_is_sub  <= (b[62:52] == 11'd0) && (b[51:0] != 52'd0);
                        b_is_inf  <= (b[62:52] == EXP_INF) && (b[51:0] == 52'd0);
                        b_is_nan  <= (b[62:52] == EXP_INF) && (b[51:0] != 52'd0);
                        b_is_snan <= (b[62:52] == EXP_INF) && (b[51:0] != 52'd0) && (b[51] == 1'b0);

                        c_is_zero <= (c[62:52] == 11'd0) && (c[51:0] == 52'd0);
                        c_is_sub  <= (c[62:52] == 11'd0) && (c[51:0] != 52'd0);
                        c_is_inf  <= (c[62:52] == EXP_INF) && (c[51:0] == 52'd0);
                        c_is_nan  <= (c[62:52] == EXP_INF) && (c[51:0] != 52'd0);
                        c_is_snan <= (c[62:52] == EXP_INF) && (c[51:0] != 52'd0) && (c[51] == 1'b0);
                    end
                end

                // ============================================================
                // S1: Special cases, compute signs, begin multiply
                // ============================================================
                S1: begin
                    // --- Compute effective signs after operation encoding ---
                    // Product sign: a_sign XOR b_sign, then negate if op[1]
                    prod_sign <= (a_sign ^ b_sign) ^ negate_prod;
                    // Addend sign: c_sign, then negate if op[0]
                    add_sign  <= c_sign ^ negate_c;

                    // --- Special case handling ---
                    // Priority: NaN > Inf*0 > Inf+(-Inf) > Inf > Zero
                    if (a_is_nan || b_is_nan || c_is_nan) begin
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= {(a_is_snan | b_is_snan | c_is_snan), 4'b0000};
                    end else if ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero)) begin
                        // Inf * 0 = NaN (NV), regardless of addend
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= 5'b10000;
                    end else if ((a_is_inf || b_is_inf) && c_is_inf) begin
                        // Inf + Inf: check signs
                        // Product is Inf with sign = prod_sign
                        // Addend is Inf with sign = add_sign
                        if (((a_sign ^ b_sign) ^ negate_prod) != (c_sign ^ negate_c)) begin
                            // Inf + (-Inf) = NaN (NV)
                            special_case   <= 1'b1;
                            special_result <= CANON_NAN;
                            special_flags  <= 5'b10000;
                        end else begin
                            // Inf + Inf (same sign) = Inf
                            special_case   <= 1'b1;
                            special_result <= {(a_sign ^ b_sign) ^ negate_prod, EXP_INF, 52'd0};
                            special_flags  <= 5'b00000;
                        end
                    end else if (a_is_inf || b_is_inf) begin
                        // Inf * finite + finite = Inf
                        special_case   <= 1'b1;
                        special_result <= {(a_sign ^ b_sign) ^ negate_prod, EXP_INF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if (c_is_inf) begin
                        // finite * finite + Inf = Inf
                        special_case   <= 1'b1;
                        special_result <= {c_sign ^ negate_c, EXP_INF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if ((a_is_zero || b_is_zero) && c_is_zero) begin
                        // 0 * x + 0: result is +/-0
                        begin : zero_plus_zero
                            reg ps, as;
                            ps = (a_sign ^ b_sign) ^ negate_prod;
                            as = c_sign ^ negate_c;
                            special_case <= 1'b1;
                            if (ps == as)
                                special_result <= {ps, 63'd0};
                            else
                                special_result <= (rm == 3'b010) ? {1'b1, 63'd0} : 64'd0;
                            special_flags <= 5'b00000;
                        end
                    end else if (a_is_zero || b_is_zero) begin
                        // 0 * x + c = c (with possibly negated sign)
                        special_case   <= 1'b1;
                        special_result <= {c_sign ^ negate_c, c_exp, c_mant[51:0]};
                        special_flags  <= 5'b00000;
                    end else begin
                        special_case <= 1'b0;
                    end

                    // --- Compute product exponent ---
                    prod_exp <= ({2'b0, (a_is_sub ? 11'd1 : a_exp)})
                              + ({2'b0, (b_is_sub ? 11'd1 : b_exp)})
                              - {2'b0, BIAS};

                    // --- Addend exponent ---
                    c_exp_ext <= {2'b0, (c_is_sub ? 11'd1 : c_exp)};

                    state <= S2;
                end

                // ============================================================
                // S2: Complete multiply, align addend to product
                // ============================================================
                S2: begin
                    if (special_case) begin
                        result <= special_result;
                        flags  <= special_flags;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= IDLE;
                    end else begin
                        // --- 53x53 multiplication ---
                        product <= a_mant * b_mant;

                        // --- Determine effective subtraction ---
                        eff_sub <= prod_sign ^ add_sign;

                        // --- Align addend to product ---
                        // Product occupies bit positions [105:0] with binary point
                        // after bit 104 (i.e., 1.xx...x with 105 fraction bits below).
                        // Actually the product is mant_a * mant_b where each is 1.52 bits,
                        // giving a 2.104 format (bits [105:0]).
                        //
                        // The addend c_mant is 1.52 (53 bits). We need to align it so
                        // that its binary point lines up with the product's binary point.
                        //
                        // Exponent difference: prod_exp - c_exp_ext
                        // If positive: product exponent is larger, shift addend right
                        // If negative: addend exponent is larger, effectively product shifts right
                        //              but we handle this by shifting addend left

                        begin : align_block
                            reg signed [12:0] exp_delta;
                            reg signed [12:0] shift_amt;
                            reg [161:0]       c_wide;
                            integer           i;

                            exp_delta = prod_exp - c_exp_ext;

                            // Place the addend mantissa at the top of the 162-bit field
                            // aligned with product bit 105 (MSB of product).
                            // c_mant is 53 bits. In the 162-bit field, position it starting
                            // at bit 159 (to leave room for carry bits at the top).
                            // Then shift based on exp_delta.
                            //
                            // The product MSB (bit 105) maps to bit 108 in the 162-bit field
                            // (leaving 3 extra MSB bits for carry in the addition).
                            // The addend leading 1 should map to bit 108 when exp_delta=0.
                            // So place c_mant[52:0] at bits [108:56] initially.
                            c_wide = {53'b0, c_mant, 56'b0};  // c_mant at [108:56]

                            // Shift by exp_delta: positive means shift right (addend smaller)
                            // negative means shift left (addend larger)
                            if (exp_delta >= 13'sd0) begin
                                // Shift addend right
                                if (exp_delta >= 13'sd162) begin
                                    aligned_c    <= 162'd0;
                                    align_sticky <= |c_mant;
                                end else begin
                                    aligned_c    <= c_wide >> exp_delta;
                                    // Collect sticky from shifted-out bits
                                    align_sticky <= 1'b0;
                                    for (i = 0; i < 162; i = i + 1) begin
                                        if (i < exp_delta)
                                            align_sticky <= align_sticky | c_wide[i];
                                    end
                                end
                                result_exp <= prod_exp;
                            end else begin
                                // Shift addend left (= shift product right effectively)
                                // Instead, we shift the addend left and track that the
                                // result exponent follows the addend
                                shift_amt = -exp_delta;
                                if (shift_amt >= 13'sd53) begin
                                    // Product is completely below addend
                                    // Place addend at MSB, product will be sticky
                                    aligned_c    <= c_wide << 53;  // maximize addend position
                                    align_sticky <= 1'b0;
                                end else begin
                                    aligned_c    <= c_wide << shift_amt;
                                    align_sticky <= 1'b0;
                                end
                                result_exp <= c_exp_ext;
                            end
                        end

                        state <= S3;
                    end
                end

                // ============================================================
                // S3: Add aligned addend to product (the "fused" operation)
                // ============================================================
                S3: begin
                    begin : add_block
                        reg [161:0] prod_wide;
                        reg [161:0] add_val;
                        reg [161:0] raw_sum;
                        reg         raw_sign;
                        reg signed [12:0] exp_delta;

                        // Place the 106-bit product in the 162-bit field
                        // Product bits [105:0] map to bits [108:3] to leave room
                        // for 3 carry bits at top
                        prod_wide = {53'b0, product, 3'b0};

                        exp_delta = prod_exp - c_exp_ext;

                        // If addend exponent was larger, we need to shift the product
                        // right by |exp_delta| instead
                        if (exp_delta < 13'sd0) begin
                            begin : prod_shift
                                reg signed [12:0] pshift;
                                reg               p_sticky;
                                integer           j;

                                pshift = -exp_delta;
                                p_sticky = 1'b0;
                                if (pshift < 13'sd162) begin
                                    for (j = 0; j < 162; j = j + 1) begin
                                        if (j < pshift)
                                            p_sticky = p_sticky | prod_wide[j];
                                    end
                                    prod_wide = prod_wide >> pshift;
                                    // OR the sticky into LSB area
                                    prod_wide[0] = prod_wide[0] | p_sticky;
                                end else begin
                                    prod_wide = 162'd0;
                                    prod_wide[0] = |product;
                                end
                            end
                        end

                        add_val = aligned_c;
                        // Incorporate alignment sticky into LSB
                        add_val[0] = add_val[0] | align_sticky;

                        // Perform addition or subtraction based on effective operation
                        if (!eff_sub) begin
                            // Same sign: add magnitudes
                            raw_sum  = prod_wide + add_val;
                            raw_sign = prod_sign;
                        end else begin
                            // Different signs: subtract smaller from larger
                            if (prod_wide >= add_val) begin
                                raw_sum  = prod_wide - add_val;
                                raw_sign = prod_sign;
                            end else begin
                                raw_sum  = add_val - prod_wide;
                                raw_sign = add_sign;
                            end
                        end

                        sum_raw    <= raw_sum;
                        sum_sign   <= raw_sign;
                        sum_exp    <= result_exp;
                        sum_sticky <= 1'b0;

                        // Check for zero result
                        if (raw_sum == 162'd0) begin
                            // Zero result: sign depends on rounding mode
                            result <= (rm == 3'b010) ? {1'b1, 63'd0} : {raw_sign, 63'd0};
                            flags  <= 5'b00000;
                            done   <= 1'b1;
                            busy   <= 1'b0;
                            state  <= IDLE;
                        end else begin
                            state <= S4;
                        end
                    end
                end

                // ============================================================
                // S4: Normalize, round, overflow/underflow, pack result
                // ============================================================
                S4: begin
                    begin : norm_round_block
                        reg [161:0]       norm_sum;
                        reg signed [12:0] norm_exp;
                        reg [6:0]         lead_zeros;
                        reg [6:0]         total_lz;
                        reg               s4_guard, s4_round, s4_sticky;
                        reg [51:0]        final_mant;
                        reg [10:0]        final_exp;
                        reg [4:0]         final_flags;
                        reg               final_sign;
                        integer           k;

                        final_flags = 5'd0;
                        final_sign  = sum_sign;
                        norm_sum    = sum_raw;
                        norm_exp    = sum_exp;

                        // --- Find leading one position ---
                        // Use LZC on top 64 bits. If all zeros there, we need
                        // to check lower bits too.
                        // lzc_input = sum_raw[161:98] (driven combinationally)
                        if (!lzc_zero) begin
                            // Leading one is in the top 64 bits
                            total_lz = lzc_count;
                        end else begin
                            // Leading one is below bit 98; estimate
                            // For simplicity, scan from MSB down
                            total_lz = 7'd64;  // at least 64 zeros in top
                            // Check next chunk: bits [97:34]
                            begin : find_lead
                                reg found;
                                found = 1'b0;
                                for (k = 97; k >= 0; k = k - 1) begin
                                    if (!found && norm_sum[k]) begin
                                        total_lz = 7'd161 - k[6:0];
                                        found = 1'b1;
                                    end
                                end
                                if (!found)
                                    total_lz = 7'd127;  // very large shift, effectively zero
                            end
                        end

                        // --- Normalize: shift left so leading 1 is at bit 161 ---
                        // Then the mantissa bits are [160:109], guard=[108],
                        // round=[107], sticky=OR([106:0])
                        // The leading 1 at bit 161 corresponds to the implicit bit.
                        begin : do_normalize
                            reg signed [12:0] shift_left;
                            reg signed [12:0] max_shift;

                            shift_left = {6'b0, total_lz};

                            // Don't shift more than exponent allows (avoid going below exp=1)
                            // Actually for FMA, the result exponent is result_exp, and we
                            // subtract the shift amount from it. Min final exp is 0 (subnormal).
                            max_shift = norm_exp + 13'sd1;  // shifting by this much gives exp=0 (subnormal)
                            if (max_shift < 13'sd0)
                                max_shift = 13'sd0;

                            if (shift_left <= max_shift || max_shift > 13'sd127) begin
                                // Normal shift
                                if (shift_left < 13'sd162)
                                    norm_sum = sum_raw << shift_left;
                                else
                                    norm_sum = 162'd0;
                                norm_exp = norm_exp - shift_left + 13'sd1;
                                // +1 because we're normalizing to bit 161 but the product
                                // MSB was at bit 108 initially, adjusted for the leading-1 position
                            end else begin
                                // Subnormal: shift only up to max_shift
                                if (max_shift > 13'sd0 && max_shift < 13'sd162)
                                    norm_sum = sum_raw << max_shift;
                                else
                                    norm_sum = sum_raw;
                                norm_exp = 13'sd0;
                            end
                        end

                        // --- Extract mantissa, GRS ---
                        // After normalization, the leading 1 should be at a known position.
                        // We want 52 mantissa bits + GRS.
                        // If leading 1 is at bit 161:
                        //   mantissa = [160:109], guard = [108], round = [107], sticky = |[106:0]
                        final_mant = norm_sum[160:109];
                        s4_guard   = norm_sum[108];
                        s4_round   = norm_sum[107];
                        s4_sticky  = |norm_sum[106:0] | sum_sticky;

                        // --- Drive rounding module ---
                        rnd_sign   = final_sign;
                        rnd_guard  = s4_guard;
                        rnd_round  = s4_round;
                        rnd_sticky = s4_sticky;
                        rnd_lsb    = final_mant[0];

                        // --- Apply rounding ---
                        if (round_up) begin
                            final_mant = final_mant + 52'd1;
                            if (final_mant == 52'd0) begin
                                // Mantissa overflowed, increment exponent
                                norm_exp = norm_exp + 13'sd1;
                            end
                        end

                        // --- Overflow check ---
                        if (norm_exp >= 13'sd2047) begin
                            final_flags = final_flags | 5'b00101;  // OF + NX
                            case (rm)
                                3'b000: begin  // RNE -> Inf
                                    final_exp  = EXP_INF;
                                    final_mant = 52'd0;
                                end
                                3'b001: begin  // RTZ -> largest finite
                                    final_exp  = 11'h7FE;
                                    final_mant = {52{1'b1}};
                                end
                                3'b010: begin  // RDN
                                    if (final_sign) begin
                                        final_exp  = EXP_INF;
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
                                        final_exp  = EXP_INF;
                                        final_mant = 52'd0;
                                    end
                                end
                                3'b100: begin  // RMM -> Inf
                                    final_exp  = EXP_INF;
                                    final_mant = 52'd0;
                                end
                                default: begin
                                    final_exp  = EXP_INF;
                                    final_mant = 52'd0;
                                end
                            endcase
                        end else if (norm_exp <= 13'sd0) begin
                            // --- Underflow: subnormal result ---
                            final_exp = 11'd0;
                            // The mantissa is already in subnormal form from limited shift
                            if (s4_guard | s4_round | s4_sticky)
                                final_flags = final_flags | 5'b00011;  // UF + NX
                        end else begin
                            // --- Normal result ---
                            final_exp = norm_exp[10:0];
                            if (s4_guard | s4_round | s4_sticky)
                                final_flags = final_flags | 5'b00001;  // NX
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
