`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for alu module (RV64FP, 64-bit datapath)
// Verifies all ALU operations including RV64I and W-variant instructions.
// Identical to RV64 version — same 64-bit ALU module.
//////////////////////////////////////////////////////////////////////////////

module sva_rv64_alu_props (
    input logic        clk,
    input logic [63:0] a,
    input logic [63:0] b,
    input logic [4:0]  alu_op,
    input logic [63:0] result,
    input logic        zero,
    input logic        lt_signed,
    input logic        lt_unsigned
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // Helper: sign-extend 32-bit value to 64 bits
    // -----------------------------------------------------------------------
    function automatic logic [63:0] sign_ext_32(input logic [31:0] val);
        return {{32{val[31]}}, val};
    endfunction

    // -----------------------------------------------------------------------
    // Basic arithmetic
    // -----------------------------------------------------------------------
    P_ADD: assert property (
        @(posedge clk) alu_op == 5'b00000 |-> result == (a + b)
    ) else $error("P_ADD: ADD result mismatch");

    P_SUB: assert property (
        @(posedge clk) alu_op == 5'b00001 |-> result == (a - b)
    ) else $error("P_SUB: SUB result mismatch");

    // -----------------------------------------------------------------------
    // Logic operations
    // -----------------------------------------------------------------------
    P_AND: assert property (
        @(posedge clk) alu_op == 5'b00010 |-> result == (a & b)
    ) else $error("P_AND: AND result mismatch");

    P_OR: assert property (
        @(posedge clk) alu_op == 5'b00011 |-> result == (a | b)
    ) else $error("P_OR: OR result mismatch");

    P_XOR: assert property (
        @(posedge clk) alu_op == 5'b00100 |-> result == (a ^ b)
    ) else $error("P_XOR: XOR result mismatch");

    // -----------------------------------------------------------------------
    // Shift operations
    // -----------------------------------------------------------------------
    P_SLL: assert property (
        @(posedge clk) alu_op == 5'b00101 |-> result == (a << b[5:0])
    ) else $error("P_SLL: SLL result mismatch");

    P_SRL: assert property (
        @(posedge clk) alu_op == 5'b00110 |-> result == (a >> b[5:0])
    ) else $error("P_SRL: SRL result mismatch");

    P_SRA: assert property (
        @(posedge clk) alu_op == 5'b00111 |-> result == ($signed(a) >>> b[5:0])
    ) else $error("P_SRA: SRA result mismatch");

    // -----------------------------------------------------------------------
    // Set-less-than operations
    // -----------------------------------------------------------------------
    P_SLT: assert property (
        @(posedge clk) alu_op == 5'b01000 |-> result == {63'd0, lt_signed}
    ) else $error("P_SLT: SLT result mismatch");

    P_SLTU: assert property (
        @(posedge clk) alu_op == 5'b01001 |-> result == {63'd0, lt_unsigned}
    ) else $error("P_SLTU: SLTU result mismatch");

    // -----------------------------------------------------------------------
    // Pass-through
    // -----------------------------------------------------------------------
    P_PASSB: assert property (
        @(posedge clk) alu_op == 5'b01010 |-> result == b
    ) else $error("P_PASSB: PASS_B result mismatch");

    // -----------------------------------------------------------------------
    // Comparison flags (always active, independent of opcode)
    // -----------------------------------------------------------------------
    P_ZERO_FLAG: assert property (
        @(posedge clk) zero == (a == b)
    ) else $error("P_ZERO_FLAG: zero flag mismatch");

    P_LT_SIGNED: assert property (
        @(posedge clk) lt_signed == ($signed(a) < $signed(b))
    ) else $error("P_LT_SIGNED: lt_signed flag mismatch");

    P_LT_UNSIGNED: assert property (
        @(posedge clk) lt_unsigned == (a < b)
    ) else $error("P_LT_UNSIGNED: lt_unsigned flag mismatch");

    // -----------------------------------------------------------------------
    // W-variant operations (32-bit ops with sign-extension to 64 bits)
    // -----------------------------------------------------------------------
    P_ADDW_SIGN_EXT: assert property (
        @(posedge clk) alu_op == 5'b10000 |->
            result[63:32] == {32{result[31]}}
    ) else $error("P_ADDW_SIGN_EXT: ADDW upper bits not sign-extended");

    P_SUBW_SIGN_EXT: assert property (
        @(posedge clk) alu_op == 5'b10001 |->
            result[63:32] == {32{result[31]}}
    ) else $error("P_SUBW_SIGN_EXT: SUBW upper bits not sign-extended");

    P_SLLW_SIGN_EXT: assert property (
        @(posedge clk) alu_op == 5'b10101 |->
            result[63:32] == {32{result[31]}}
    ) else $error("P_SLLW_SIGN_EXT: SLLW upper bits not sign-extended");

    P_SRLW_SIGN_EXT: assert property (
        @(posedge clk) alu_op == 5'b10110 |->
            result[63:32] == {32{result[31]}}
    ) else $error("P_SRLW_SIGN_EXT: SRLW upper bits not sign-extended");

    P_SRAW_SIGN_EXT: assert property (
        @(posedge clk) alu_op == 5'b10111 |->
            result[63:32] == {32{result[31]}}
    ) else $error("P_SRAW_SIGN_EXT: SRAW upper bits not sign-extended");

    // -----------------------------------------------------------------------
    // Default: undefined opcodes produce zero
    // -----------------------------------------------------------------------
    P_DEFAULT: assert property (
        @(posedge clk)
            alu_op != 5'b00000 && alu_op != 5'b00001 &&
            alu_op != 5'b00010 && alu_op != 5'b00011 &&
            alu_op != 5'b00100 && alu_op != 5'b00101 &&
            alu_op != 5'b00110 && alu_op != 5'b00111 &&
            alu_op != 5'b01000 && alu_op != 5'b01001 &&
            alu_op != 5'b01010 &&
            alu_op != 5'b10000 && alu_op != 5'b10001 &&
            alu_op != 5'b10101 && alu_op != 5'b10110 &&
            alu_op != 5'b10111
        |-> result == 64'h0
    ) else $error("P_DEFAULT: undefined opcode did not produce zero");

endmodule
