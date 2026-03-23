`timescale 1ns / 1ps
//
// fp_cmp.v — FEQ.D, FLT.D, FLE.D, FMIN.D, FMAX.D (combinational, 1 cycle)
//

module fp_cmp (
    input  [63:0] a,
    input  [63:0] b,
    input  [2:0]  op,          // 0=FEQ, 1=FLT, 2=FLE, 3=FMIN, 4=FMAX
    output reg [63:0] result,  // FP result for FMIN/FMAX; 0 or 1 for comparisons
    output reg [4:0]  flags,
    output        result_is_int // 1 for FEQ/FLT/FLE, 0 for FMIN/FMAX
);

    // -----------------------------------------------------------------
    // Unpack
    // -----------------------------------------------------------------
    wire        a_sign = a[63];
    wire [10:0] a_exp  = a[62:52];
    wire [51:0] a_mant = a[51:0];

    wire        b_sign = b[63];
    wire [10:0] b_exp  = b[62:52];
    wire [51:0] b_mant = b[51:0];

    // NaN detection
    wire a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'b0);
    wire b_is_nan  = (b_exp == 11'h7FF) && (b_mant != 52'b0);
    wire a_is_snan = a_is_nan && (a_mant[51] == 1'b0);
    wire b_is_snan = b_is_nan && (b_mant[51] == 1'b0);
    wire any_nan   = a_is_nan || b_is_nan;
    wire any_snan  = a_is_snan || b_is_snan;

    // Zero detection (both +0 and -0 are equal)
    wire a_is_zero = (a_exp == 11'h000) && (a_mant == 52'b0);
    wire b_is_zero = (b_exp == 11'h000) && (b_mant == 52'b0);
    wire both_zero = a_is_zero && b_is_zero;

    // -----------------------------------------------------------------
    // Magnitude comparison on {exp, mant}
    // -----------------------------------------------------------------
    wire [62:0] a_mag = a[62:0];  // unsigned magnitude
    wire [62:0] b_mag = b[62:0];

    wire mag_eq = (a_mag == b_mag);
    wire mag_lt = (a_mag <  b_mag);
    wire mag_gt = (a_mag >  b_mag);

    // -----------------------------------------------------------------
    // Signed less-than logic (a < b), treating +0 == -0
    // -----------------------------------------------------------------
    reg a_lt_b;
    always @(*) begin
        a_lt_b = 1'b0;
        if (both_zero) begin
            a_lt_b = 1'b0;                           // +0 == -0
        end else if (a_sign != b_sign) begin
            a_lt_b = a_sign;                          // negative < positive
        end else if (a_sign == 1'b0) begin
            // Both positive: smaller magnitude is less
            a_lt_b = mag_lt;
        end else begin
            // Both negative: larger magnitude is less
            a_lt_b = mag_gt;
        end
    end

    // Equality: bitwise equal or both zero
    wire a_eq_b = (a == b) || both_zero;

    // -----------------------------------------------------------------
    // Canonical NaN
    // -----------------------------------------------------------------
    localparam [63:0] CANON_NAN = 64'h7FF8_0000_0000_0000;

    // -----------------------------------------------------------------
    // Main output logic
    // -----------------------------------------------------------------
    // Flags: {NV, DZ, OF, UF, NX}
    localparam NV = 4;

    always @(*) begin
        result = 64'b0;
        flags  = 5'b0;

        case (op)
            // =============================================================
            // FEQ.D  (op=0): NV only on sNaN
            // =============================================================
            3'd0: begin
                if (any_nan) begin
                    result = 64'd0;
                    if (any_snan) flags[NV] = 1'b1;
                end else begin
                    result = {63'b0, a_eq_b};
                end
            end

            // =============================================================
            // FLT.D  (op=1): NV on any NaN
            // =============================================================
            3'd1: begin
                if (any_nan) begin
                    result    = 64'd0;
                    flags[NV] = 1'b1;
                end else begin
                    result = {63'b0, a_lt_b};
                end
            end

            // =============================================================
            // FLE.D  (op=2): NV on any NaN
            // =============================================================
            3'd2: begin
                if (any_nan) begin
                    result    = 64'd0;
                    flags[NV] = 1'b1;
                end else begin
                    result = {63'b0, (a_lt_b || a_eq_b)};
                end
            end

            // =============================================================
            // FMIN.D (op=3): return smaller; prefer -0 over +0
            // =============================================================
            3'd3: begin
                if (a_is_nan && b_is_nan) begin
                    result = CANON_NAN;
                    if (any_snan) flags[NV] = 1'b1;
                end else if (a_is_nan) begin
                    result = b;
                    if (a_is_snan) flags[NV] = 1'b1;
                end else if (b_is_nan) begin
                    result = a;
                    if (b_is_snan) flags[NV] = 1'b1;
                end else if (both_zero) begin
                    // Prefer -0 for MIN
                    result = (a_sign) ? a : b;
                end else begin
                    result = a_lt_b ? a : b;
                end
            end

            // =============================================================
            // FMAX.D (op=4): return larger; prefer +0 over -0
            // =============================================================
            3'd4: begin
                if (a_is_nan && b_is_nan) begin
                    result = CANON_NAN;
                    if (any_snan) flags[NV] = 1'b1;
                end else if (a_is_nan) begin
                    result = b;
                    if (a_is_snan) flags[NV] = 1'b1;
                end else if (b_is_nan) begin
                    result = a;
                    if (b_is_snan) flags[NV] = 1'b1;
                end else if (both_zero) begin
                    // Prefer +0 for MAX
                    result = (!a_sign) ? a : b;
                end else begin
                    // a > b means NOT (a < b) AND NOT equal
                    result = (!a_lt_b && !a_eq_b) ? a : b;
                end
            end

            default: begin
                result = 64'b0;
                flags  = 5'b0;
            end
        endcase
    end

    // FEQ/FLT/FLE result goes to integer register file
    assign result_is_int = (op <= 3'd2);

endmodule
