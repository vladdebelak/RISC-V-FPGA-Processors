// ============================================================================
// fp_mul.v — IEEE 754 Double-Precision Floating-Point Multiplier
// FMUL.D for RV64IFD
// 3-cycle pipelined state machine (IDLE -> STAGE1 -> STAGE2 -> STAGE3)
// Vivado 2020.2 targeting 7-series FPGAs (~400 LUTs + 9 DSP48E1)
// ============================================================================

module fp_mul (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,       // pulse to begin operation
    input  wire [63:0] a,           // IEEE 754 operand A
    input  wire [63:0] b,           // IEEE 754 operand B
    input  wire [2:0]  rm,          // rounding mode
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
    // Constants
    // ========================================================================
    localparam EXP_INF   = 11'h7FF;
    localparam BIAS      = 11'd1023;
    localparam CANON_NAN = 64'h7FF8_0000_0000_0000;

    // ========================================================================
    // Stage 1 registers — unpacked operands and special-case detection
    // ========================================================================
    reg        a_sign, b_sign, res_sign;
    reg [10:0] a_exp, b_exp;
    reg [52:0] a_mant, b_mant;         // 53 bits: {implicit, stored[51:0]}
    reg        a_is_zero, b_is_zero;
    reg        a_is_inf,  b_is_inf;
    reg        a_is_nan,  b_is_nan;
    reg        a_is_snan, b_is_snan;
    reg        a_is_sub,  b_is_sub;

    // Special case handling
    reg        special_case;
    reg [63:0] special_result;
    reg [4:0]  special_flags;

    // Exponent computation (needs extra bit for overflow detection)
    reg signed [12:0] res_exp_s;        // signed to detect underflow

    // ========================================================================
    // Stage 2 registers — multiplication product
    // ========================================================================
    reg [105:0] product;                // 53 x 53 = 106-bit product

    // ========================================================================
    // Rounding function (shared logic)
    // ========================================================================
    `include "fp_round_func.vh"

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

            a_sign <= 0; b_sign <= 0; res_sign <= 0;
            a_exp  <= 0; b_exp  <= 0;
            a_mant <= 0; b_mant <= 0;
            a_is_zero <= 0; b_is_zero <= 0;
            a_is_inf  <= 0; b_is_inf  <= 0;
            a_is_nan  <= 0; b_is_nan  <= 0;
            a_is_snan <= 0; b_is_snan <= 0;
            a_is_sub  <= 0; b_is_sub  <= 0;
            special_case <= 0; special_result <= 0; special_flags <= 0;
            res_exp_s <= 0;
            product <= 0;
        end else begin
            // Default: done is single-cycle pulse
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
                        // Unpack operand A
                        // ====================================================
                        a_sign <= a[63];
                        a_exp  <= a[62:52];
                        a_mant <= (a[62:52] == 11'd0) ? {1'b0, a[51:0]}   // subnormal
                                                       : {1'b1, a[51:0]};  // normal

                        // ====================================================
                        // Unpack operand B
                        // ====================================================
                        b_sign <= b[63];
                        b_exp  <= b[62:52];
                        b_mant <= (b[62:52] == 11'd0) ? {1'b0, b[51:0]}
                                                       : {1'b1, b[51:0]};

                        // ====================================================
                        // Classify operands
                        // ====================================================
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

                        // ====================================================
                        // Result sign is always XOR of input signs
                        // ====================================================
                        res_sign <= a[63] ^ b[63];
                    end
                end

                // ============================================================
                // STAGE1: Handle special cases, compute exponent, start multiply
                // ============================================================
                STAGE1: begin
                    // --- Special case handling (priority: NaN > Inf*0 > Inf > Zero) ---
                    if (a_is_nan || b_is_nan) begin
                        // NaN input -> canonical NaN, NV if sNaN
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= {(a_is_snan | b_is_snan), 4'b0000};
                    end else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
                        // 0 * Inf = NaN, NV flag
                        special_case   <= 1'b1;
                        special_result <= CANON_NAN;
                        special_flags  <= 5'b10000;  // NV
                    end else if (a_is_inf || b_is_inf) begin
                        // Inf * nonzero = +/-Inf
                        special_case   <= 1'b1;
                        special_result <= {res_sign, EXP_INF, 52'd0};
                        special_flags  <= 5'b00000;
                    end else if (a_is_zero || b_is_zero) begin
                        // 0 * anything = +/-0
                        special_case   <= 1'b1;
                        special_result <= {res_sign, 63'd0};
                        special_flags  <= 5'b00000;
                    end else begin
                        special_case <= 1'b0;
                    end

                    // --- Compute result exponent (signed to detect over/underflow) ---
                    // For subnormals, the effective exponent is 1 (not 0), but the
                    // mantissa has a leading 0. We handle subnormals by using exp=1
                    // in the bias calculation.
                    res_exp_s <= ({2'b0, (a_is_sub ? 11'd1 : a_exp)})
                               + ({2'b0, (b_is_sub ? 11'd1 : b_exp)})
                               - {2'b0, BIAS};

                    // --- Register mantissas for multiplication in STAGE2 ---
                    // a_mant and b_mant are already registered from IDLE

                    state <= STAGE2;
                end

                // ============================================================
                // STAGE2: Perform 53x53-bit multiplication
                // ============================================================
                STAGE2: begin
                    if (special_case) begin
                        // Early-out for special cases
                        result <= special_result;
                        flags  <= special_flags;
                        done   <= 1'b1;
                        busy   <= 1'b0;
                        state  <= IDLE;
                    end else begin
                        // 53 x 53 = 106-bit unsigned multiply
                        // Vivado will automatically infer DSP48E1 cascade for this
                        product <= a_mant * b_mant;
                        state   <= STAGE3;
                    end
                end

                // ============================================================
                // STAGE3: Normalize, round, handle overflow/underflow, pack
                // ============================================================
                STAGE3: begin
                    begin : stage3_block
                        reg [105:0] norm_prod;
                        reg signed [12:0] norm_exp;
                        reg        s3_guard, s3_round, s3_sticky;
                        reg [51:0] final_mant;
                        reg [10:0] final_exp;
                        reg [4:0]  final_flags;

                        final_flags = 5'd0;

                        // --- Normalization ---
                        // Product of two 1.xx numbers is in range [1.0, 4.0)
                        // product[105] set means product >= 2.0, need to shift right
                        // product[104] set (and not [105]) means product in [1.0, 2.0)
                        if (product[105]) begin
                            // Product in [2.0, 4.0): shift right by 1, increment exponent
                            // Bit layout after right shift:
                            //   [105] = 0 (was carry)
                            //   [104:53] = 52-bit stored mantissa
                            //   [52] = guard
                            //   [51] = round
                            //   [50:0] = sticky candidates
                            norm_prod = product;
                            norm_exp  = res_exp_s + 1;
                            s3_guard  = product[52];
                            s3_round  = product[51];
                            s3_sticky = |product[50:0];
                            final_mant = product[104:53];
                        end else begin
                            // Product in [1.0, 2.0): no shift needed
                            //   [104] = leading 1 (implicit)
                            //   [103:52] = 52-bit stored mantissa
                            //   [51] = guard
                            //   [50] = round
                            //   [49:0] = sticky candidates
                            norm_prod = product;
                            norm_exp  = res_exp_s;
                            s3_guard  = product[51];
                            s3_round  = product[50];
                            s3_sticky = |product[49:0];
                            final_mant = product[103:52];
                        end

                        // --- Apply rounding (use shared rounding function) ---
                        if (fp_do_round(res_sign, s3_guard, s3_round, s3_sticky, final_mant[0], rm)) begin
                            final_mant = final_mant + 52'd1;
                            if (final_mant == 52'd0) begin
                                norm_exp = norm_exp + 1;
                            end
                        end

                        // --- Overflow detection ---
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
                                    if (res_sign) begin
                                        final_exp  = EXP_INF;
                                        final_mant = 52'd0;
                                    end else begin
                                        final_exp  = 11'h7FE;
                                        final_mant = {52{1'b1}};
                                    end
                                end
                                3'b011: begin  // RUP
                                    if (res_sign) begin
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
                            // --- Underflow: result is subnormal or zero ---
                            begin : underflow_block
                                reg signed [12:0] shift_right;
                                reg [105:0]       sub_prod;
                                reg               uf_sticky;

                                // How many positions to right-shift to reach exp=0
                                shift_right = 13'sd1 - norm_exp;

                                if (shift_right >= 13'sd53) begin
                                    // Completely shifted out -> zero
                                    final_exp  = 11'd0;
                                    final_mant = 52'd0;
                                    // Sticky from the entire product
                                    uf_sticky = |product;
                                end else begin
                                    // Partial shift: subnormal result
                                    // Shift the mantissa right by shift_right, collecting sticky
                                    if (product[105]) begin
                                        sub_prod = product >> 1;  // already accounted for in norm_exp
                                    end else begin
                                        sub_prod = product;
                                    end

                                    // Shift right by (shift_right) more positions
                                    begin : subnorm_shift
                                        reg [52:0] mant_full;
                                        reg [52:0] shifted_mant;
                                        integer i;

                                        if (product[105])
                                            mant_full = product[105:53];
                                        else
                                            mant_full = product[104:52];

                                        shifted_mant = mant_full >> shift_right;
                                        final_mant = shifted_mant[51:0];

                                        // Sticky: OR all bits shifted out
                                        uf_sticky = s3_guard | s3_round | s3_sticky;
                                        for (i = 0; i < 53; i = i + 1) begin
                                            if (i < shift_right)
                                                uf_sticky = uf_sticky | mant_full[i];
                                        end
                                    end
                                    final_exp = 11'd0;
                                end

                                if (uf_sticky || s3_guard || s3_round || s3_sticky) begin
                                    final_flags = final_flags | 5'b00011;  // UF + NX
                                end
                            end
                        end else begin
                            // --- Normal result ---
                            final_exp = norm_exp[10:0];
                            if (s3_guard | s3_round | s3_sticky)
                                final_flags = final_flags | 5'b00001;  // NX
                        end

                        // --- Pack final result ---
                        result <= {res_sign, final_exp, final_mant};
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
