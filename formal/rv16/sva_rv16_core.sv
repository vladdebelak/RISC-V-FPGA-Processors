`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for rv16_core module
// Minimal pipeline sanity checks for the 16-bit RISC-V core.
//////////////////////////////////////////////////////////////////////////////

module sva_rv16_core_props (
    input logic        clk,
    input logic        rst,
    input logic [15:0] instr_addr,
    input logic [15:0] instr_data,
    input logic [15:0] data_addr,
    input logic [15:0] data_wdata,
    input logic [15:0] data_rdata,
    input logic        data_we
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // P_PC_ALIGNED: Instruction address is always half-word aligned (bit 0 == 0)
    // -----------------------------------------------------------------------
    P_PC_ALIGNED: assert property (
        @(posedge clk) !rst |-> instr_addr[0] == 1'b0
    ) else $error("P_PC_ALIGNED: instruction address is not half-word aligned");

    // -----------------------------------------------------------------------
    // P_NO_WRITE_IN_RESET: No data memory writes during reset
    // -----------------------------------------------------------------------
    P_NO_WRITE_IN_RESET: assert property (
        @(posedge clk) rst |-> !data_we
    ) else $error("P_NO_WRITE_IN_RESET: data_we asserted during reset");

    // -----------------------------------------------------------------------
    // C_BRANCH_TAKEN: Cover a branch being taken (non-sequential PC change)
    // -----------------------------------------------------------------------
    C_BRANCH_TAKEN: cover property (
        @(posedge clk) !rst ##1 (!rst && (instr_addr != ($past(instr_addr) + 16'd2)))
    );

endmodule
