`timescale 1ns / 1ps
//
// fp_conv.v — Integer <-> FP conversions (FCVT) and bitwise moves (FMV)
// FCVT operations take 2 cycles; FMV operations complete in 1 cycle.
// Instantiates fp_round for int->FP rounding and fp_lzc for leading-zero count.
//

module fp_conv (
    input         clk,
    input         rst,
    input         start,
    input  [3:0]  op,
    // 0=FCVT.W.D   (fp->s32)    1=FCVT.WU.D  (fp->u32)
    // 2=FCVT.L.D   (fp->s64)    3=FCVT.LU.D  (fp->u64)
    // 4=FCVT.D.W   (s32->fp)    5=FCVT.D.WU  (u32->fp)
    // 6=FCVT.D.L   (s64->fp)    7=FCVT.D.LU  (u64->fp)
    // 8=FMV.X.D    (fp bits->int)  9=FMV.D.X  (int bits->fp)
    input  [63:0] fp_in,     // FP source
    input  [63:0] int_in,    // Integer source
    input  [2:0]  rm,
    output reg [63:0] result,
    output reg [4:0]  flags,
    output reg        done,
    output reg        busy,
    output reg        result_is_int
);

    // -----------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------
    localparam [63:0] CANON_NAN = 64'h7FF8_0000_0000_0000;
    localparam [10:0] EXP_MAX   = 11'h7FF;
    localparam [10:0] EXP_BIAS  = 11'd1023;

    localparam NV = 4, DZ = 3, OF = 2, UF = 1, NX = 0;

    // -----------------------------------------------------------------
    // LZC instance for int->FP
    // -----------------------------------------------------------------
    reg  [63:0] lzc_data;
    wire [6:0]  lzc_count;
    wire        lzc_zero;

    fp_lzc u_lzc (
        .data  (lzc_data),
        .count (lzc_count),
        .zero  (lzc_zero)
    );

    // -----------------------------------------------------------------
    // Rounding function (shared logic)
    // -----------------------------------------------------------------
    `include "fp_round_func.vh"

    // -----------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------
    localparam S_IDLE   = 2'd0;
    localparam S_CYCLE1 = 2'd1;
    localparam S_CYCLE2 = 2'd2;
    reg [1:0] state;

    // -----------------------------------------------------------------
    // Working registers
    // -----------------------------------------------------------------
    reg [3:0]  op_r;
    reg [2:0]  rm_r;

    // FP->Int working regs
    reg        fp_sign;
    reg [10:0] fp_exp;
    reg [52:0] fp_mant;    // {implicit, frac}
    reg        fp_is_nan, fp_is_inf, fp_is_zero;
    reg signed [12:0] shift_amt;

    // Int->FP working regs
    reg        int_sign;       // sign of integer (for signed conversions)
    reg [63:0] int_abs;        // absolute value
    reg [10:0] int_exp;
    reg [63:0] int_shifted;    // mantissa shifted into position

    // -----------------------------------------------------------------
    // Main logic
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            busy         <= 1'b0;
            result       <= 64'b0;
            flags        <= 5'b0;
            result_is_int <= 1'b0;
            lzc_data     <= 64'b0;
            op_r         <= 4'b0;
            rm_r         <= 3'b0;
            fp_sign      <= 1'b0;
            fp_exp       <= 11'b0;
            fp_mant      <= 53'b0;
            fp_is_nan    <= 1'b0;
            fp_is_inf    <= 1'b0;
            fp_is_zero   <= 1'b0;
            shift_amt    <= 13'b0;
            int_sign     <= 1'b0;
            int_abs      <= 64'b0;
            int_exp      <= 11'b0;
            int_shifted  <= 64'b0;
        end else begin
            done <= 1'b0;

            case (state)
                // =====================================================
                // IDLE — accept new operation
                // =====================================================
                S_IDLE: begin
                    if (start) begin
                        op_r <= op;
                        rm_r <= rm;

                        // FMV operations: combinational, done immediately
                        if (op == 4'd8) begin
                            // FMV.X.D: bitwise copy FP -> int
                            result        <= fp_in;
                            flags         <= 5'b0;
                            result_is_int <= 1'b1;
                            done          <= 1'b1;
                        end else if (op == 4'd9) begin
                            // FMV.D.X: bitwise copy int -> FP
                            result        <= int_in;
                            flags         <= 5'b0;
                            result_is_int <= 1'b0;
                            done          <= 1'b1;
                        end else begin
                            busy  <= 1'b1;
                            state <= S_CYCLE1;

                            if (op <= 4'd3) begin
                                // -------------------------------------------
                                // FP -> Int: unpack FP value
                                // -------------------------------------------
                                fp_sign <= fp_in[63];
                                fp_exp  <= fp_in[62:52];
                                fp_mant <= (fp_in[62:52] == 11'b0) ? {1'b0, fp_in[51:0]}
                                                                   : {1'b1, fp_in[51:0]};
                                fp_is_nan  <= (fp_in[62:52] == EXP_MAX) && (fp_in[51:0] != 52'b0);
                                fp_is_inf  <= (fp_in[62:52] == EXP_MAX) && (fp_in[51:0] == 52'b0);
                                fp_is_zero <= (fp_in[62:52] == 11'b0)   && (fp_in[51:0] == 52'b0);
                                result_is_int <= 1'b1;
                            end else begin
                                // -------------------------------------------
                                // Int -> FP: prepare absolute value
                                // -------------------------------------------
                                result_is_int <= 1'b0;

                                case (op)
                                    4'd4: begin  // FCVT.D.W (signed 32)
                                        int_sign <= int_in[31];
                                        int_abs  <= int_in[31] ? {32'b0, (~int_in[31:0] + 32'd1)}
                                                               : {32'b0, int_in[31:0]};
                                    end
                                    4'd5: begin  // FCVT.D.WU (unsigned 32)
                                        int_sign <= 1'b0;
                                        int_abs  <= {32'b0, int_in[31:0]};
                                    end
                                    4'd6: begin  // FCVT.D.L (signed 64)
                                        int_sign <= int_in[63];
                                        int_abs  <= int_in[63] ? (~int_in + 64'd1) : int_in;
                                    end
                                    4'd7: begin  // FCVT.D.LU (unsigned 64)
                                        int_sign <= 1'b0;
                                        int_abs  <= int_in;
                                    end
                                    default: begin
                                        int_sign <= 1'b0;
                                        int_abs  <= 64'b0;
                                    end
                                endcase
                            end
                        end
                    end
                end

                // =====================================================
                // CYCLE 1 — compute shift / LZC
                // =====================================================
                S_CYCLE1: begin
                    state <= S_CYCLE2;

                    if (op_r <= 4'd3) begin
                        // FP -> Int: compute how many bits to shift
                        // The mantissa represents 1.xxxx * 2^(exp-1023)
                        // Integer value magnitude = mant >> (52 - (exp-1023))
                        //                         = mant << ((exp-1023) - 52) if exp > 1075
                        shift_amt <= $signed({2'b0, fp_exp}) - $signed(13'd1023);
                    end else begin
                        // Int -> FP: feed absolute value to LZC
                        lzc_data <= int_abs;
                        // LZC result available combinationally, used in CYCLE2
                    end
                end

                // =====================================================
                // CYCLE 2 — produce final result
                // =====================================================
                S_CYCLE2: begin
                    flags <= 5'b0;
                    if (op_r <= 4'd3) begin
                        // -------------------------------------------
                        // FP -> Int conversion
                        // -------------------------------------------
                        begin : fp2int_blk
                            reg [63:0] int_val;
                            reg        out_of_range;
                            reg        inexact;
                            reg [63:0] max_pos, max_neg;  // clamping limits
                            reg signed [12:0] shft;
                            reg [63:0] shifted_mant;
                            reg [63:0] frac_bits;

                            out_of_range = 1'b0;
                            inexact      = 1'b0;
                            int_val      = 64'b0;
                            shft         = shift_amt;

                            // Set clamping limits based on target type
                            case (op_r)
                                4'd0: begin max_pos = 64'h0000_0000_7FFF_FFFF; max_neg = 64'hFFFF_FFFF_8000_0000; end // W
                                4'd1: begin max_pos = 64'h0000_0000_FFFF_FFFF; max_neg = 64'h0000_0000_0000_0000; end // WU
                                4'd2: begin max_pos = 64'h7FFF_FFFF_FFFF_FFFF; max_neg = 64'h8000_0000_0000_0000; end // L
                                4'd3: begin max_pos = 64'hFFFF_FFFF_FFFF_FFFF; max_neg = 64'h0000_0000_0000_0000; end // LU
                                default: begin max_pos = 64'b0; max_neg = 64'b0; end
                            endcase

                            if (fp_is_nan || fp_is_inf) begin
                                out_of_range = 1'b1;
                                if (fp_is_nan || !fp_sign)
                                    int_val = max_pos;
                                else
                                    int_val = max_neg;
                            end else if (fp_is_zero) begin
                                int_val = 64'b0;
                            end else if (shft < 0) begin
                                // |value| < 1.0 — result is 0 (possibly inexact)
                                int_val = 64'b0;
                                inexact = 1'b1;
                                // But need to check rounding
                                // For simplicity: if shft == -1, guard = mant[52], etc.
                                // We round toward the appropriate direction
                                // Apply rounding (use shared rounding function)
                                begin : fp2int_sub1_vars
                                    reg loc_guard, loc_round;
                                    loc_guard = (shft == -13'sd1) ? fp_mant[52] : 1'b0;
                                    loc_round = (shft == -13'sd1) ? fp_mant[51] :
                                               (shft == -13'sd2) ? fp_mant[52] : 1'b0;
                                if (fp_do_round(fp_sign, loc_guard, loc_round, 1'b1, 1'b0, rm_r)) begin
                                    int_val = 64'd1;
                                    // Check if rounded result overflows unsigned zero case
                                    if (fp_sign && (op_r == 4'd1 || op_r == 4'd3)) begin
                                        // Negative rounded to 1 but target is unsigned
                                        out_of_range = 1'b1;
                                        int_val = max_neg; // 0
                                    end
                                end
                                end // fp2int_sub1_vars
                            end else if (shft > 63) begin
                                // Definitely out of range
                                out_of_range = 1'b1;
                                int_val = fp_sign ? max_neg : max_pos;
                            end else begin
                                // Normal conversion: shift mantissa
                                if (shft >= 52) begin
                                    shifted_mant = {11'b0, fp_mant} << (shft - 13'sd52);
                                    inexact = 1'b0;
                                end else begin
                                    shifted_mant = {11'b0, fp_mant} >> (13'sd52 - shft);
                                    // Fractional bits for rounding
                                    frac_bits = {11'b0, fp_mant} << (shft + 13'sd12);
                                    // guard = frac_bits[63], round = frac_bits[62],
                                    // sticky = |frac_bits[61:0]
                                    inexact = frac_bits[63] | frac_bits[62] | (|frac_bits[61:0]);
                                    // Apply rounding (use shared rounding function)
                                    shifted_mant = shifted_mant + {63'b0, fp_do_round(fp_sign, frac_bits[63], frac_bits[62], |frac_bits[61:0], shifted_mant[0], rm_r)};
                                end

                                int_val = shifted_mant;

                                // Apply sign
                                if (fp_sign) begin
                                    if (op_r == 4'd1 || op_r == 4'd3) begin
                                        // Unsigned target: negative value is out of range
                                        // (unless value rounds to zero)
                                        if (int_val != 64'b0) begin
                                            out_of_range = 1'b1;
                                            int_val = max_neg; // 0
                                        end
                                    end else begin
                                        int_val = ~int_val + 64'd1; // negate (two's complement)
                                    end
                                end

                                // Range check for signed targets
                                if (!out_of_range) begin
                                    case (op_r)
                                        4'd0: begin // W: check [-2^31, 2^31-1]
                                            if (!fp_sign && shifted_mant > 64'h7FFF_FFFF) begin
                                                out_of_range = 1'b1; int_val = max_pos;
                                            end else if (fp_sign && shifted_mant > 64'h8000_0000) begin
                                                out_of_range = 1'b1; int_val = max_neg;
                                            end
                                            // Sign-extend W result to 64 bits
                                            if (!out_of_range)
                                                int_val = {{32{int_val[31]}}, int_val[31:0]};
                                        end
                                        4'd1: begin // WU
                                            if (shifted_mant > 64'hFFFF_FFFF) begin
                                                out_of_range = 1'b1; int_val = max_pos;
                                            end
                                            // Sign-extend WU result to 64 bits
                                            if (!out_of_range)
                                                int_val = {{32{int_val[31]}}, int_val[31:0]};
                                        end
                                        4'd2: begin // L
                                            if (!fp_sign && shifted_mant > 64'h7FFF_FFFF_FFFF_FFFF) begin
                                                out_of_range = 1'b1; int_val = max_pos;
                                            end
                                            // For negative, the negated value overflow is
                                            // handled by the negate step above
                                        end
                                        4'd3: begin // LU — already handled unsigned negative above
                                        end
                                        default: ;
                                    endcase
                                end
                            end

                            result <= int_val;
                            if (out_of_range)
                                flags[NV] <= 1'b1;
                            else if (inexact)
                                flags[NX] <= 1'b1;
                        end
                    end else begin
                        // -------------------------------------------
                        // Int -> FP conversion
                        // -------------------------------------------
                        begin : int2fp_blk
                            reg [63:0] abs_val;
                            reg [6:0]  lz;
                            reg [10:0] exp_val;
                            reg [63:0] shifted;
                            reg        g_bit, rnd_bit, s_bit;
                            reg [51:0] mant_out;
                            reg [52:0] mant_rounded;
                            reg        inexact;

                            abs_val = int_abs;

                            // Feed LZC (combinational) — must be before reading lzc_count
                            lzc_data = abs_val;

                            lz      = lzc_count;

                            if (abs_val == 64'b0) begin
                                // Zero integer -> +0.0 or -0.0
                                result <= {int_sign, 63'b0};
                                flags  <= 5'b0;
                            end else begin
                                // Exponent: number of significant bits = 64 - lz
                                // Value = abs_val = 1.xxx * 2^(63-lz)  after normalizing
                                // IEEE exp = (63 - lz) + 1023
                                exp_val = 11'd1086 - {4'b0, lz};  // 1086 = 63 + 1023

                                // Shift mantissa so MSB (the leading 1) is at bit 63
                                shifted = abs_val << lz;

                                // shifted[63] = 1 (implicit bit)
                                // shifted[62:11] = 52 mantissa bits
                                // shifted[10] = guard
                                // shifted[9]  = round
                                // |shifted[8:0] = sticky
                                mant_out = shifted[62:11];
                                g_bit    = shifted[10];
                                rnd_bit  = shifted[9];
                                s_bit    = |shifted[8:0];

                                inexact = g_bit | rnd_bit | s_bit;

                                // For W/WU (32-bit sources), the integer fits in 32 bits
                                // so at most 32 significant bits — always exact in double
                                if (op_r == 4'd4 || op_r == 4'd5) begin
                                    inexact = 1'b0;
                                    g_bit   = 1'b0;
                                    rnd_bit = 1'b0;
                                    s_bit   = 1'b0;
                                end

                                // Apply rounding (use shared rounding function)
                                mant_rounded = {1'b0, mant_out} + {52'b0, fp_do_round(int_sign, g_bit, rnd_bit, s_bit, shifted[11], rm_r)};

                                // If mantissa overflows (all 1s + round up)
                                if (mant_rounded[52]) begin
                                    exp_val  = exp_val + 11'd1;
                                    mant_out = mant_rounded[52:1]; // shift right
                                end else begin
                                    mant_out = mant_rounded[51:0];
                                end

                                result <= {int_sign, exp_val, mant_out};
                                if (inexact)
                                    flags[NX] <= 1'b1;
                                else
                                    flags <= 5'b0;
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
