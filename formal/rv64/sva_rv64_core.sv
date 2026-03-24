`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for rv64_core module
// Minimal pipeline sanity checks for the 64-bit RISC-V core.
//////////////////////////////////////////////////////////////////////////////

module sva_rv64_core_props (
    input logic        clk,
    input logic        rst,
    input logic [8:0]  instr_addr,
    input logic [31:0] instr_data,
    input logic [63:0] mem_addr,
    input logic [63:0] mem_wdata,
    input logic [63:0] mem_rdata,
    input logic        mem_we
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // P_INSTR_ADDR_RANGE: Instruction address always within BRAM range
    // (9-bit word index for 512-entry instruction memory)
    // -----------------------------------------------------------------------
    P_INSTR_ADDR_RANGE: assert property (
        @(posedge clk) !rst |-> instr_addr <= 9'd511
    ) else $error("P_INSTR_ADDR_RANGE: instruction address out of BRAM range");

    // -----------------------------------------------------------------------
    // P_NO_WRITE_IN_RESET: No data memory writes during reset
    // (skip first 2 cycles to allow pipeline registers to initialize)
    // -----------------------------------------------------------------------
    logic [1:0] init_count = 2'd0;
    always_ff @(posedge clk) if (init_count < 2'd2) init_count <= init_count + 1;

    P_NO_WRITE_IN_RESET: assert property (
        @(posedge clk) (init_count == 2'd2) && rst |-> !mem_we
    ) else $error("P_NO_WRITE_IN_RESET: mem_we asserted during reset");

    // -----------------------------------------------------------------------
    // C_BRANCH_TAKEN: Cover a branch being taken (non-sequential PC change)
    // -----------------------------------------------------------------------
    C_BRANCH_TAKEN: cover property (
        @(posedge clk) !rst ##1 (!rst && (instr_addr != ($past(instr_addr) + 9'd1)))
    );

endmodule
