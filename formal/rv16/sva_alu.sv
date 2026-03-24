`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for alu module (RV16, 16-bit datapath)
// Verifies all ALU operations, zero flag, and default behavior.
//////////////////////////////////////////////////////////////////////////////

module sva_rv16_alu_props (
    input logic        clk,
    input logic [15:0] a,
    input logic [15:0] b,
    input logic [3:0]  alu_op,
    input logic [15:0] result,
    input logic        zero
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // Arithmetic operations
    // -----------------------------------------------------------------------
    P_ADD: assert property (
        @(posedge clk) alu_op == 4'b0000 |-> result == (a + b)
    ) else $error("P_ADD: ADD result mismatch");

    P_SUB: assert property (
        @(posedge clk) alu_op == 4'b0001 |-> result == (a - b)
    ) else $error("P_SUB: SUB result mismatch");

    // -----------------------------------------------------------------------
    // Logic operations
    // -----------------------------------------------------------------------
    P_AND: assert property (
        @(posedge clk) alu_op == 4'b0010 |-> result == (a & b)
    ) else $error("P_AND: AND result mismatch");

    P_OR: assert property (
        @(posedge clk) alu_op == 4'b0011 |-> result == (a | b)
    ) else $error("P_OR: OR result mismatch");

    P_XOR: assert property (
        @(posedge clk) alu_op == 4'b0100 |-> result == (a ^ b)
    ) else $error("P_XOR: XOR result mismatch");

    // -----------------------------------------------------------------------
    // Pass-through
    // -----------------------------------------------------------------------
    P_PASSB: assert property (
        @(posedge clk) alu_op == 4'b0101 |-> result == b
    ) else $error("P_PASSB: PASS_B result mismatch");

    // -----------------------------------------------------------------------
    // Default: undefined opcodes produce zero
    // -----------------------------------------------------------------------
    P_DEFAULT: assert property (
        @(posedge clk) alu_op > 4'b0101 |-> result == 16'h0
    ) else $error("P_DEFAULT: undefined opcode did not produce zero");

    // -----------------------------------------------------------------------
    // Zero flag
    // -----------------------------------------------------------------------
    P_ZERO_SET: assert property (
        @(posedge clk) result == 16'h0 |-> zero
    ) else $error("P_ZERO_SET: zero flag not set when result is 0");

    P_ZERO_CLEAR: assert property (
        @(posedge clk) result != 16'h0 |-> !zero
    ) else $error("P_ZERO_CLEAR: zero flag set when result is non-zero");

endmodule
