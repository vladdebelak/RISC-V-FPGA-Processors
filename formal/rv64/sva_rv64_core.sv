`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for rv64_core module
// Minimal pipeline sanity checks for the 64-bit RISC-V core.
//////////////////////////////////////////////////////////////////////////////

module sva_rv64_core_props (
    input logic        clk,
    input logic        rst,
    input logic [63:0] instr_addr,
    input logic [31:0] instr_data,
    input logic [63:0] data_addr,
    input logic [63:0] data_wdata,
    input logic [63:0] data_rdata,
    input logic        data_we
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // P_PC_ALIGNED: Instruction address is always word-aligned (bits [1:0] == 0)
    // RV64 uses 32-bit instructions, so PC must be 4-byte aligned.
    // -----------------------------------------------------------------------
    P_PC_ALIGNED: assert property (
        @(posedge clk) !rst |-> instr_addr[1:0] == 2'b00
    ) else $error("P_PC_ALIGNED: instruction address is not word-aligned");

    // -----------------------------------------------------------------------
    // P_NO_WRITE_IN_RESET: No data memory writes during reset
    // -----------------------------------------------------------------------
    P_NO_WRITE_IN_RESET: assert property (
        @(posedge clk) rst |-> !data_we
    ) else $error("P_NO_WRITE_IN_RESET: data_we asserted during reset");

    // -----------------------------------------------------------------------
    // P_PC_IN_RANGE: PC stays within a reasonable address range
    // (upper bits should not be all ones unless in kernel space)
    // -----------------------------------------------------------------------
    P_PC_IN_RANGE: assert property (
        @(posedge clk) !rst |-> instr_addr < 64'h0000_0001_0000_0000
    ) else $error("P_PC_IN_RANGE: instruction address out of expected range");

    // -----------------------------------------------------------------------
    // C_BRANCH_TAKEN: Cover a branch being taken (non-sequential PC change)
    // -----------------------------------------------------------------------
    C_BRANCH_TAKEN: cover property (
        @(posedge clk) !rst ##1 (!rst && (instr_addr != ($past(instr_addr) + 64'd4)))
    );

endmodule
