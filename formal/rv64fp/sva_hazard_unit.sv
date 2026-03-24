`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for hazard_unit module (RV64FP)
// Verifies data forwarding, load-use stalls, FPU busy stalls, branch
// flushes, and forwarding priority logic.
//////////////////////////////////////////////////////////////////////////////

module sva_hazard_unit_props (
    input logic       clk,

    // From decode -- integer
    input logic [4:0] id_rs1_addr,
    input logic [4:0] id_rs2_addr,
    input logic       id_rs1_used,
    input logic       id_rs2_used,

    // From ID/EX pipeline register
    input logic [4:0] idex_rd,
    input logic       idex_reg_we,
    input logic       idex_fp_reg_we,
    input logic       idex_mem_re,

    // From EX/MEM pipeline register
    input logic [4:0] exmem_rd,
    input logic       exmem_reg_we,
    input logic       exmem_fp_reg_we,
    input logic       exmem_mem_re,

    // From MEM/WB pipeline register
    input logic [4:0] memwb_rd,
    input logic       memwb_reg_we,
    input logic       memwb_fp_reg_we,

    // FP register source addresses
    input logic [4:0] id_fp_rs1_addr,
    input logic [4:0] id_fp_rs2_addr,
    input logic [4:0] id_fp_rs3_addr,
    input logic       id_fp_rs1_used,
    input logic       id_fp_rs2_used,
    input logic       id_fp_rs3_used,

    // FPU busy
    input logic       fpu_busy,

    // Branch / jump
    input logic       branch_taken,
    input logic       jalr_taken,

    // Forwarding select outputs
    input logic [1:0] fwd_rs1_sel,
    input logic [1:0] fwd_rs2_sel,
    input logic [1:0] fwd_fp_rs1_sel,
    input logic [1:0] fwd_fp_rs2_sel,
    input logic [1:0] fwd_fp_rs3_sel,

    // Stall / flush outputs
    input logic       stall_if,
    input logic       stall_id,
    input logic       stall_ex,
    input logic       flush_if,
    input logic       flush_id,
    input logic       flush_ex
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // Internal: recompute load-use hazard for assertions
    // -----------------------------------------------------------------------
    wire load_use_idex = idex_mem_re && (
        (id_rs1_used && (idex_rd == id_rs1_addr) && (idex_rd != 5'd0)) ||
        (id_rs2_used && (idex_rd == id_rs2_addr) && (idex_rd != 5'd0)) ||
        (id_fp_rs1_used && (idex_rd == id_fp_rs1_addr)) ||
        (id_fp_rs2_used && (idex_rd == id_fp_rs2_addr)) ||
        (id_fp_rs3_used && (idex_rd == id_fp_rs3_addr))
    );

    wire load_use_exmem = exmem_mem_re && (
        (id_rs1_used && (exmem_rd == id_rs1_addr) && (exmem_rd != 5'd0)) ||
        (id_rs2_used && (exmem_rd == id_rs2_addr) && (exmem_rd != 5'd0)) ||
        (id_fp_rs1_used && (exmem_rd == id_fp_rs1_addr)) ||
        (id_fp_rs2_used && (exmem_rd == id_fp_rs2_addr)) ||
        (id_fp_rs3_used && (exmem_rd == id_fp_rs3_addr))
    );

    wire load_use_hazard = load_use_idex | load_use_exmem;

    // =======================================================================
    // Load-use stall properties
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_LOAD_USE_STALLS_IF: Load-use hazard stalls IF stage
    // -----------------------------------------------------------------------
    P_LOAD_USE_STALLS_IF: assert property (
        @(posedge clk)
        idex_mem_re && id_rs1_used && (idex_rd == id_rs1_addr) && (idex_rd != 5'd0)
        |-> stall_if
    ) else $error("P_LOAD_USE_STALLS_IF: IF not stalled on load-use hazard");

    // -----------------------------------------------------------------------
    // P_LOAD_USE_STALLS_ID: Load-use hazard stalls ID stage
    // -----------------------------------------------------------------------
    P_LOAD_USE_STALLS_ID: assert property (
        @(posedge clk)
        idex_mem_re && id_rs1_used && (idex_rd == id_rs1_addr) && (idex_rd != 5'd0)
        |-> stall_id
    ) else $error("P_LOAD_USE_STALLS_ID: ID not stalled on load-use hazard");

    // =======================================================================
    // FPU busy stall properties
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_FPU_BUSY_STALL_IF: FPU busy stalls IF stage
    // -----------------------------------------------------------------------
    P_FPU_BUSY_STALL_IF: assert property (
        @(posedge clk) fpu_busy |-> stall_if
    ) else $error("P_FPU_BUSY_STALL_IF: IF not stalled when FPU busy");

    // -----------------------------------------------------------------------
    // P_FPU_BUSY_STALL_ID: FPU busy stalls ID stage
    // -----------------------------------------------------------------------
    P_FPU_BUSY_STALL_ID: assert property (
        @(posedge clk) fpu_busy |-> stall_id
    ) else $error("P_FPU_BUSY_STALL_ID: ID not stalled when FPU busy");

    // -----------------------------------------------------------------------
    // P_FPU_BUSY_STALL_EX: FPU busy stalls EX stage
    // -----------------------------------------------------------------------
    P_FPU_BUSY_STALL_EX: assert property (
        @(posedge clk) fpu_busy |-> stall_ex
    ) else $error("P_FPU_BUSY_STALL_EX: EX not stalled when FPU busy");

    // =======================================================================
    // Branch flush properties
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_BRANCH_FLUSH_IF: Branch taken flushes IF stage
    // -----------------------------------------------------------------------
    P_BRANCH_FLUSH_IF: assert property (
        @(posedge clk) branch_taken |-> flush_if
    ) else $error("P_BRANCH_FLUSH_IF: IF not flushed on branch taken");

    // -----------------------------------------------------------------------
    // P_BRANCH_FLUSH_ID: Branch taken flushes ID stage
    // -----------------------------------------------------------------------
    P_BRANCH_FLUSH_ID: assert property (
        @(posedge clk) branch_taken |-> flush_id
    ) else $error("P_BRANCH_FLUSH_ID: ID not flushed on branch taken");

    // -----------------------------------------------------------------------
    // P_JALR_FLUSH_IF: JALR taken flushes IF stage
    // -----------------------------------------------------------------------
    P_JALR_FLUSH_IF: assert property (
        @(posedge clk) jalr_taken |-> flush_if
    ) else $error("P_JALR_FLUSH_IF: IF not flushed on JALR taken");

    // -----------------------------------------------------------------------
    // P_JALR_FLUSH_ID: JALR taken flushes ID stage
    // -----------------------------------------------------------------------
    P_JALR_FLUSH_ID: assert property (
        @(posedge clk) jalr_taken |-> flush_id
    ) else $error("P_JALR_FLUSH_ID: ID not flushed on JALR taken");

    // =======================================================================
    // Integer forwarding priority (EX=01 > MEM=10 > WB=11)
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_FWD_RS1_EX_PRIORITY: EX stage match (non-load) selects fwd=01
    // -----------------------------------------------------------------------
    P_FWD_RS1_EX_PRIORITY: assert property (
        @(posedge clk)
        idex_reg_we && (idex_rd != 5'd0) && (idex_rd == id_rs1_addr) &&
        id_rs1_used && !idex_mem_re
        |-> fwd_rs1_sel == 2'b01
    ) else $error("P_FWD_RS1_EX_PRIORITY: EX forwarding not selected for rs1");

    // -----------------------------------------------------------------------
    // P_NO_FWD_X0: Forwarding never activates for integer register x0
    // -----------------------------------------------------------------------
    P_NO_FWD_X0: assert property (
        @(posedge clk)
        fwd_rs1_sel != 2'b00 && id_rs1_used
        |-> id_rs1_addr != 5'd0 || !idex_reg_we
    ) else $error("P_NO_FWD_X0: forwarding activated for x0");

    // =======================================================================
    // FP forwarding (f0 IS allowed -- no != 0 check)
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_FP_FWD_RS1_EX: FP EX stage match selects fwd=01
    // -----------------------------------------------------------------------
    P_FP_FWD_RS1_EX: assert property (
        @(posedge clk)
        idex_fp_reg_we && (idex_rd == id_fp_rs1_addr) && id_fp_rs1_used
        |-> fwd_fp_rs1_sel == 2'b01
    ) else $error("P_FP_FWD_RS1_EX: FP EX forwarding not selected for fp_rs1");

    // -----------------------------------------------------------------------
    // C_FP_FWD_F0: Cover forwarding to f0
    // -----------------------------------------------------------------------
    C_FP_FWD_F0: cover property (
        @(posedge clk) id_fp_rs1_addr == 5'd0 && fwd_fp_rs1_sel != 2'b00
    );

    // =======================================================================
    // Load-use flush (bubble insertion)
    // =======================================================================

    // -----------------------------------------------------------------------
    // P_LOAD_USE_FLUSHES_EX: Load-use hazard inserts bubble in EX
    // -----------------------------------------------------------------------
    P_LOAD_USE_FLUSHES_EX: assert property (
        @(posedge clk) load_use_hazard |-> flush_ex
    ) else $error("P_LOAD_USE_FLUSHES_EX: EX not flushed on load-use hazard");

endmodule
