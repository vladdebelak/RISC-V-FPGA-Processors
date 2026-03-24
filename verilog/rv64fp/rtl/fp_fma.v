// ============================================================================
// fp_fma.v — IEEE 754 Double-Precision Fused Multiply-Add
// FMADD.D / FMSUB.D / FNMSUB.D / FNMADD.D for RV64IFD
// Implements as: result = ±(a*b) ± c  (sign depends on op)
//
// RISC-V FMA operations:
//   FMADD  (op=00):  +(a*b) + c
//   FMSUB  (op=01):  +(a*b) - c
//   FNMSUB (op=10):  -(a*b) + c
//   FNMADD (op=11):  -(a*b) - c
//
// 5-cycle state machine: IDLE -> S1 -> S2 -> S3 -> S4
// Optimized: 116-bit accumulator with barrel-shift alignment
// ============================================================================

module fp_fma (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [1:0]  op,
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [63:0] c,
    input  wire [2:0]  rm,
    output reg  [63:0] result,
    output reg  [4:0]  flags,
    output reg         done,
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

    // Accumulator width: 116 bits
    // Product (106 bits) at [109:4], with bits [3:0] for GRS+extra,
    // bits [115:110] for carry headroom
    localparam ACC_W = 116;

    // ========================================================================
    // Registered inputs and intermediate values
    // ========================================================================
    reg        a_sign, b_sign, c_sign;
    reg [10:0] a_exp, b_exp, c_exp;
    reg [52:0] a_mant, b_mant, c_mant;

    reg        a_is_zero, b_is_zero, c_is_zero;
    reg        a_is_inf,  b_is_inf,  c_is_inf;
    reg        a_is_nan,  b_is_nan,  c_is_nan;
    reg        a_is_snan, b_is_snan, c_is_snan;
    reg        a_is_sub,  b_is_sub,  c_is_sub;

    reg        prod_sign;
    reg        add_sign;
    reg        negate_prod;
    reg        negate_c;

    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // Product
    reg [105:0]       product;      // 53x53 = 106 bits
    reg signed [12:0] prod_exp;
    reg signed [12:0] c_exp_ext;
    reg               eff_sub;

    // Addition stage
    reg signed [12:0] result_exp;

    // Narrower accumulator
    reg [ACC_W-1:0] sum_raw;
    reg             sum_sign;
    reg signed [12:0] sum_exp;

    // LZC — reuse two instances via two passes
    reg  [63:0] lzc_input;
    wire [6:0]  lzc_count;
    wire        lzc_zero;

    fp_lzc u_lzc (
        .data  (lzc_input),
        .count (lzc_count),
        .zero  (lzc_zero)
    );

    // Rounding function (shared logic)
    `include "fp_round_func.vh"

    // LZC input: top 64 bits of sum_raw (bits [115:52])
    always @(*) begin
        lzc_input = sum_raw[ACC_W-1:ACC_W-64];
    end

    // Second LZC for lower half
    reg  [63:0] lzc2_input;
    wire [6:0]  lzc2_count;
    wire        lzc2_zero;

    fp_lzc u_lzc2 (
        .data  (lzc2_input),
        .count (lzc2_count),
        .zero  (lzc2_zero)
    );

    always @(*) begin
        lzc2_input = {sum_raw[ACC_W-65:0], {(128-ACC_W){1'b0}}};
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
            eff_sub <= 0; result_exp <= 0;
            sum_raw <= 0; sum_sign <= 0; sum_exp <= 0;
        end else begin
            done <= 1'b0;

            case (state)
                // ============================================================
                // IDLE
                // ============================================================
                IDLE: begin
                    if (start) begin
                        state <= S1;
                        busy  <= 1'b1;
                        flags <= 5'd0;

                        negate_prod <= op[1];
                        negate_c    <= op[0];

                        a_sign <= a[63];
                        a_exp  <= a[62:52];
                        a_mant <= (a[62:52] == 11'd0) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};

                        b_sign <= b[63];
                        b_exp  <= b[62:52];
                        b_mant <= (b[62:52] == 11'd0) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};

                        c_sign <= c[63];
                        c_exp  <= c[62:52];
                        c_mant <= (c[62:52] == 11'd0) ? {1'b0, c[51:0]} : {1'b1, c[51:0]};

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
                // S1: Special cases, compute signs, start multiply
                // ============================================================
                S1: begin
                    prod_sign <= (a_sign ^ b_sign) ^ negate_prod;
                    add_sign  <= c_sign ^ negate_c;

                    // Special case handling
                    if (a_is_nan || b_is_nan || c_is_nan) begin
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= {(a_is_snan | b_is_snan | c_is_snan), 4'b0000};
                    end else if ((a_is_inf || b_is_inf) && (a_is_zero || b_is_zero)) begin
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= 5'b10000;
                    end else if ((a_is_inf || b_is_inf) && c_is_inf) begin
                        if (((a_sign ^ b_sign) ^ negate_prod) != (c_sign ^ negate_c)) begin
                            special_case   <= 1'b1;
                            special_result <= CANON_NAN;
                            special_flags  <= 5'b10000;
                        end else begin
                            special_case   <= 1'b1;
                            special_result <= {(a_sign ^ b_sign) ^ negate_prod, EXP_INF, 52'd0};
                            special_flags  <= 5'b00000;
                        end
                    end else if (a_is_inf || b_is_inf) begin
                        special_case   <= 1'b1;
                        special_result <= {(a_sign ^ b_sign) ^ negate_prod, EXP_INF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if (c_is_inf) begin
                        special_case   <= 1'b1;
                        special_result <= {c_sign ^ negate_c, EXP_INF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if ((a_is_zero || b_is_zero) && c_is_zero) begin
                        begin : zero_plus_zero
                            reg ps, as_sign;
                            ps = (a_sign ^ b_sign) ^ negate_prod;
                            as_sign = c_sign ^ negate_c;
                            special_case <= 1'b1;
                            if (ps == as_sign)
                                special_result <= {ps, 63'd0};
                            else
                                special_result <= (rm == 3'b010) ? {1'b1, 63'd0} : 64'd0;
                            special_flags <= 5'b00000;
                        end
                    end else if (a_is_zero || b_is_zero) begin
                        special_case   <= 1'b1;
                        special_result <= {c_sign ^ negate_c, c_exp, c_mant[51:0]};
                        special_flags  <= 5'b00000;
                    end else begin
                        special_case <= 1'b0;
                    end

                    // Product exponent
                    prod_exp <= ({2'b0, (a_is_sub ? 11'd1 : a_exp)})
                              + ({2'b0, (b_is_sub ? 11'd1 : b_exp)})
                              - {2'b0, BIAS};

                    c_exp_ext <= {2'b0, (c_is_sub ? 11'd1 : c_exp)};

                    state <= S2;
                end

                // ============================================================
                // S2: Multiply mantissas
                // ============================================================
                S2: begin
                    if (special_case) begin
                        result <= special_result;
                        flags  <= special_flags;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= IDLE;
                    end else begin
                        // 53x53 multiply
                        product <= a_mant * b_mant;
                        eff_sub <= prod_sign ^ add_sign;
                        state   <= S3;
                    end
                end

                // ============================================================
                // S3: Align and add using 116-bit accumulator
                // ============================================================
                S3: begin
                    begin : add_block
                        // Product is 106 bits [105:0], value = product * 2^(prod_exp - 104)
                        // Addend is 53 bits c_mant[52:0], value = c_mant * 2^(c_exp_ext - 52)
                        //
                        // Strategy: place both in a 116-bit field.
                        // Product at [109:4] (106 bits), with [3:0] for sub-product precision
                        // and [115:110] for carry headroom.
                        // Bit 108 = 2^prod_exp.
                        //
                        // Addend leading bit (c_mant[52]) should be at position
                        // 108 + (c_exp_ext - prod_exp) = 108 + exp_delta.
                        // Addend LSB at (56 + exp_delta).
                        //
                        // If exp_delta places addend above bit 115 or below bit 0,
                        // handle as edge case.

                        reg [ACC_W-1:0] prod_wide;
                        reg [ACC_W-1:0] c_wide;
                        reg [ACC_W-1:0] raw_sum;
                        reg             raw_sign;
                        reg signed [12:0] exp_delta;
                        reg signed [12:0] c_top_pos;
                        reg               c_sticky;
                        reg signed [12:0] local_result_exp;

                        // Place product
                        prod_wide = {{(ACC_W-110){1'b0}}, product, 4'b0};

                        // Compute alignment
                        exp_delta = c_exp_ext - prod_exp;
                        c_top_pos = 13'sd108 + exp_delta;

                        c_wide = {ACC_W{1'b0}};
                        c_sticky = 1'b0;
                        local_result_exp = prod_exp;

                        if (c_top_pos >= $signed(ACC_W)) begin
                            // Addend dominates: place addend at top, product -> sticky
                            // Adjust: addend MSB at bit 115, so shift = 115 - 52 = 63 for LSB
                            c_wide = {{(ACC_W-53){1'b0}}, c_mant} << (ACC_W - 1 - 52);
                            prod_wide = {ACC_W{1'b0}};
                            prod_wide[0] = |product;
                            local_result_exp = c_exp_ext;
                        end else if (c_top_pos < 13'sd0) begin
                            // Addend completely below accumulator -> sticky
                            c_sticky = |c_mant;
                            prod_wide[0] = prod_wide[0] | c_sticky;
                        end else begin
                            // Normal: shift addend into position using barrel shifter
                            // c_mant[52] goes to bit c_top_pos
                            // c_mant[0] goes to bit (c_top_pos - 52)
                            begin : place_addend
                                reg signed [12:0] c_bot_pos;
                                reg [ACC_W-1:0] c_shifted;
                                reg signed [12:0] shift_amt;

                                c_bot_pos = c_top_pos - 13'sd52;

                                if (c_bot_pos >= 13'sd0) begin
                                    // Entire addend fits in accumulator
                                    shift_amt = c_bot_pos;
                                    if (shift_amt < ACC_W)
                                        c_wide = {{(ACC_W-53){1'b0}}, c_mant} << shift_amt;
                                end else begin
                                    // Some low bits of addend fall below bit 0
                                    // Shift addend right by (-c_bot_pos), collect sticky
                                    shift_amt = -c_bot_pos;
                                    if (shift_amt < 53) begin
                                        c_wide = {{(ACC_W-53){1'b0}}, c_mant} >> shift_amt;
                                        // Collect sticky from shifted-out bits
                                        begin : sticky_collect
                                            reg [52:0] mask;
                                            mask = (53'd1 << shift_amt) - 53'd1;
                                            c_sticky = |(c_mant & mask);
                                        end
                                    end else begin
                                        // All addend bits shifted out
                                        c_sticky = |c_mant;
                                    end
                                    prod_wide[0] = prod_wide[0] | c_sticky;
                                end
                            end
                        end

                        // Perform addition or subtraction
                        if (!eff_sub) begin
                            raw_sum  = prod_wide + c_wide;
                            raw_sign = prod_sign;
                        end else begin
                            if (prod_wide >= c_wide) begin
                                raw_sum  = prod_wide - c_wide;
                                raw_sign = prod_sign;
                            end else begin
                                raw_sum  = c_wide - prod_wide;
                                raw_sign = add_sign;
                            end
                        end

                        sum_raw  <= raw_sum;
                        sum_sign <= raw_sign;
                        sum_exp  <= local_result_exp;

                        if (raw_sum == {ACC_W{1'b0}}) begin
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
                // S4: Normalize, round, pack
                // ============================================================
                S4: begin
                    begin : norm_round_block
                        reg [ACC_W-1:0]   norm_sum;
                        reg signed [12:0] norm_exp;
                        reg [6:0]         total_lz;
                        reg               s4_guard, s4_round, s4_sticky;
                        reg [51:0]        final_mant;
                        reg [10:0]        final_exp;
                        reg [4:0]         final_flags;
                        reg               final_sign;

                        final_flags = 5'd0;
                        final_sign  = sum_sign;
                        norm_sum    = sum_raw;
                        norm_exp    = sum_exp;

                        // Find leading one using two LZC instances
                        // lzc_input = sum_raw[115:52] (top 64 bits)
                        // lzc2_input = {sum_raw[51:0], 12'b0} (bottom 52 bits, padded)
                        if (!lzc_zero) begin
                            total_lz = lzc_count;
                        end else if (!lzc2_zero) begin
                            total_lz = 7'd64 + lzc2_count;
                        end else begin
                            total_lz = 7'd127; // effectively all zeros
                        end

                        // After shifting left by total_lz, leading 1 at bit (ACC_W-1) = 115.
                        // Mantissa = [114:63], guard=[62], round=[61], sticky=|[60:0]
                        //
                        // Result biased exponent:
                        // bit 108 = 2^norm_exp, leading 1 at bit (ACC_W-1 - total_lz)
                        // = 115 - total_lz.
                        // Value = 2^(norm_exp + (115-total_lz) - 108)
                        //       = 2^(norm_exp + 7 - total_lz)
                        // Biased exp = norm_exp + 7 - total_lz

                        begin : do_normalize
                            reg signed [12:0] shift_left;
                            reg signed [12:0] target_exp;

                            shift_left = {6'b0, total_lz};
                            target_exp = norm_exp + 13'sd7 - shift_left;

                            if (target_exp < 13'sd1) begin
                                shift_left = norm_exp + 13'sd7;
                                if (shift_left < 13'sd0)
                                    shift_left = 13'sd0;
                                if (shift_left > $signed(ACC_W - 1))
                                    shift_left = ACC_W - 1;
                                norm_exp = 13'sd0;
                            end else begin
                                norm_exp = target_exp;
                            end

                            if (shift_left < $signed(ACC_W) && shift_left >= 13'sd0)
                                norm_sum = sum_raw << shift_left;
                            else if (shift_left >= $signed(ACC_W))
                                norm_sum = {ACC_W{1'b0}};
                        end

                        // Extract mantissa, GRS
                        // Leading 1 at bit 115 (implicit), mantissa = [114:63]
                        final_mant = norm_sum[ACC_W-2:ACC_W-53];
                        s4_guard   = norm_sum[ACC_W-54];
                        s4_round   = norm_sum[ACC_W-55];
                        s4_sticky  = |norm_sum[ACC_W-56:0];

                        // Apply rounding (use shared rounding function)
                        if (fp_do_round(final_sign, s4_guard, s4_round, s4_sticky, final_mant[0], rm)) begin
                            final_mant = final_mant + 52'd1;
                            if (final_mant == 52'd0) begin
                                norm_exp = norm_exp + 13'sd1;
                            end
                        end

                        // Overflow check
                        if (norm_exp >= 13'sd2047) begin
                            final_flags = final_flags | 5'b00101;
                            case (rm)
                                3'b000: begin final_exp = EXP_INF; final_mant = 52'd0; end
                                3'b001: begin final_exp = 11'h7FE; final_mant = {52{1'b1}}; end
                                3'b010: begin
                                    if (final_sign) begin final_exp = EXP_INF; final_mant = 52'd0; end
                                    else begin final_exp = 11'h7FE; final_mant = {52{1'b1}}; end
                                end
                                3'b011: begin
                                    if (final_sign) begin final_exp = 11'h7FE; final_mant = {52{1'b1}}; end
                                    else begin final_exp = EXP_INF; final_mant = 52'd0; end
                                end
                                3'b100: begin final_exp = EXP_INF; final_mant = 52'd0; end
                                default: begin final_exp = EXP_INF; final_mant = 52'd0; end
                            endcase
                        end else if (norm_exp <= 13'sd0) begin
                            final_exp = 11'd0;
                            if (s4_guard | s4_round | s4_sticky)
                                final_flags = final_flags | 5'b00011;
                        end else begin
                            final_exp = norm_exp[10:0];
                            if (s4_guard | s4_round | s4_sticky)
                                final_flags = final_flags | 5'b00001;
                        end

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
