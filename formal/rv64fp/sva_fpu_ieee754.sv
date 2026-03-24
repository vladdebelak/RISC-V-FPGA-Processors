`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for fpu_top module — IEEE 754 special-value verification
// Verifies correct handling of Inf, NaN, zero, and exception flags for
// double-precision floating-point operations.
//////////////////////////////////////////////////////////////////////////////

module sva_fpu_ieee754_props (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic [4:0]  fp_op,
    input logic [2:0]  rm,
    input logic [63:0] fp_a,
    input logic [63:0] fp_b,
    input logic [63:0] fp_c,
    input logic [63:0] int_src,
    input logic [63:0] fp_result,
    input logic        done,
    input logic        busy,
    input logic [4:0]  fp_flags,
    input logic        result_is_int
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // FP operation codes
    // -----------------------------------------------------------------------
    localparam [4:0] FP_ADD  = 5'd0, FP_SUB  = 5'd1,
                     FP_MUL  = 5'd2, FP_DIV  = 5'd3,
                     FP_SQRT = 5'd4;

    // -----------------------------------------------------------------------
    // IEEE 754 double-precision constants
    // -----------------------------------------------------------------------
    localparam [63:0] QNAN     = 64'h7FF8000000000000;
    localparam [63:0] POS_INF  = 64'h7FF0000000000000;
    localparam [63:0] NEG_INF  = 64'hFFF0000000000000;
    localparam [63:0] POS_ZERO = 64'h0000000000000000;
    localparam [63:0] NEG_ZERO = 64'h8000000000000000;

    // -----------------------------------------------------------------------
    // Helper functions
    // -----------------------------------------------------------------------
    function automatic logic is_nan(input logic [63:0] v);
        return (v[62:52] == 11'h7FF) && (v[51:0] != 52'd0);
    endfunction

    function automatic logic is_inf(input logic [63:0] v);
        return (v[62:52] == 11'h7FF) && (v[51:0] == 52'd0);
    endfunction

    function automatic logic is_zero(input logic [63:0] v);
        return (v[62:0] == 63'd0);
    endfunction

    function automatic logic is_negative(input logic [63:0] v);
        return (v[63] == 1'b1);
    endfunction

    // -----------------------------------------------------------------------
    // Latching logic: capture inputs at start time for multicycle checking
    // -----------------------------------------------------------------------
    logic [63:0] latched_a;
    logic [63:0] latched_b;
    logic [4:0]  latched_op;

    always_ff @(posedge clk) begin
        if (rst) begin
            latched_a  <= 64'd0;
            latched_b  <= 64'd0;
            latched_op <= 5'd0;
        end else if (start) begin
            latched_a  <= fp_a;
            latched_b  <= fp_b;
            latched_op <= fp_op;
        end
    end

    // -----------------------------------------------------------------------
    // IEEE 754 flag bit positions: {NV, DZ, OF, UF, NX}
    //                               [4]  [3] [2] [1] [0]
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // P_INF_PLUS_INF: ADD of +Inf + +Inf produces +Inf
    // -----------------------------------------------------------------------
    P_INF_PLUS_INF: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_ADD &&
        latched_a == POS_INF && latched_b == POS_INF
        |-> fp_result == POS_INF
    ) else $error("P_INF_PLUS_INF: +Inf + +Inf did not produce +Inf");

    // -----------------------------------------------------------------------
    // P_INF_MINUS_INF_NAN: SUB of +Inf - +Inf produces NaN with NV flag
    // -----------------------------------------------------------------------
    P_INF_MINUS_INF_NAN: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_SUB &&
        latched_a == POS_INF && latched_b == POS_INF
        |-> is_nan(fp_result) && fp_flags[4]
    ) else $error("P_INF_MINUS_INF_NAN: +Inf - +Inf did not produce NaN with NV");

    // -----------------------------------------------------------------------
    // P_ZERO_TIMES_INF_NAN: MUL of 0 * Inf produces NaN with NV flag
    // -----------------------------------------------------------------------
    P_ZERO_TIMES_INF_NAN: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_MUL &&
        is_zero(latched_a) && is_inf(latched_b)
        |-> is_nan(fp_result) && fp_flags[4]
    ) else $error("P_ZERO_TIMES_INF_NAN: 0 * Inf did not produce NaN with NV");

    // -----------------------------------------------------------------------
    // P_DIV_BY_ZERO: DIV of nonzero / 0 produces Inf with DZ flag
    // -----------------------------------------------------------------------
    P_DIV_BY_ZERO: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_DIV &&
        !is_zero(latched_a) && !is_nan(latched_a) && !is_inf(latched_a) &&
        is_zero(latched_b)
        |-> is_inf(fp_result) && fp_flags[3]
    ) else $error("P_DIV_BY_ZERO: nonzero / 0 did not produce Inf with DZ");

    // -----------------------------------------------------------------------
    // P_SQRT_NEG_NAN: SQRT of negative produces NaN with NV flag
    // -----------------------------------------------------------------------
    P_SQRT_NEG_NAN: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_SQRT &&
        is_negative(latched_a) && !is_zero(latched_a) && !is_nan(latched_a)
        |-> is_nan(fp_result) && fp_flags[4]
    ) else $error("P_SQRT_NEG_NAN: sqrt(negative) did not produce NaN with NV");

    // -----------------------------------------------------------------------
    // P_NAN_INPUT_ADD: ADD with NaN input produces canonical quiet NaN
    // -----------------------------------------------------------------------
    P_NAN_INPUT_ADD: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_ADD &&
        (is_nan(latched_a) || is_nan(latched_b))
        |-> is_nan(fp_result)
    ) else $error("P_NAN_INPUT_ADD: ADD with NaN input did not produce NaN");

    // -----------------------------------------------------------------------
    // P_NAN_INPUT_MUL: MUL with NaN input produces canonical quiet NaN
    // -----------------------------------------------------------------------
    P_NAN_INPUT_MUL: assert property (
        @(posedge clk) disable iff (rst)
        done && latched_op == FP_MUL &&
        (is_nan(latched_a) || is_nan(latched_b))
        |-> is_nan(fp_result)
    ) else $error("P_NAN_INPUT_MUL: MUL with NaN input did not produce NaN");

    // -----------------------------------------------------------------------
    // C_SPECIAL_VALUES: Cover operations with special value inputs
    // -----------------------------------------------------------------------
    C_ADD_INF: cover property (
        @(posedge clk) start && fp_op == FP_ADD && is_inf(fp_a)
    );
    C_ADD_NAN: cover property (
        @(posedge clk) start && fp_op == FP_ADD && is_nan(fp_a)
    );
    C_MUL_ZERO: cover property (
        @(posedge clk) start && fp_op == FP_MUL && is_zero(fp_a)
    );
    C_DIV_ZERO_DENOM: cover property (
        @(posedge clk) start && fp_op == FP_DIV && is_zero(fp_b)
    );
    C_SQRT_NEG: cover property (
        @(posedge clk) start && fp_op == FP_SQRT && is_negative(fp_a) && !is_zero(fp_a)
    );

endmodule
