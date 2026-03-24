`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for rv64fp_core module
// Minimal top-level properties — avoids hierarchical references for
// SymbiYosys compatibility.
//////////////////////////////////////////////////////////////////////////////

module sva_rv64fp_pipeline_props (
    input logic        clk,
    input logic        rst,
    input logic [8:0]  instr_addr,
    input logic [31:0] instr_data,
    input logic [63:0] mem_addr,
    input logic [63:0] mem_wdata,
    input logic [63:0] mem_rdata,
    input logic        mem_we,
    input logic        mem_re,
    input logic [1:0]  mem_size,
    input logic        mem_unsigned
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // P_INSTR_ADDR_RANGE: Instruction address always within BRAM range
    // -----------------------------------------------------------------------
    P_INSTR_ADDR_RANGE: assert property (
        @(posedge clk) disable iff (rst)
        instr_addr <= 9'd511
    ) else $error("P_INSTR_ADDR_RANGE: instruction address out of BRAM range");

    // -----------------------------------------------------------------------
    // C_MEM_WRITE: Cover a memory write occurring
    // -----------------------------------------------------------------------
    C_MEM_WRITE: cover property (
        @(posedge clk) !rst && mem_we
    );

    // -----------------------------------------------------------------------
    // C_MEM_READ: Cover a memory read occurring
    // -----------------------------------------------------------------------
    C_MEM_READ: cover property (
        @(posedge clk) !rst && mem_re
    );

endmodule
