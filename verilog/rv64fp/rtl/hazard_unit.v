`timescale 1ns / 1ps
//
// hazard_unit.v — Data forwarding, stall, and flush control
// for a 5-stage RV64IFD pipeline.
//

module hazard_unit (
    // From decode — current instruction in ID stage
    input [4:0] id_rs1_addr,
    input [4:0] id_rs2_addr,
    input       id_rs1_used,
    input       id_rs2_used,

    // From ID/EX pipeline register (instruction currently in EX stage)
    input [4:0] idex_rd,
    input       idex_reg_we,
    input       idex_fp_reg_we,
    input       idex_mem_re,        // load in EX stage

    // From EX/MEM pipeline register
    input [4:0] exmem_rd,
    input       exmem_reg_we,
    input       exmem_fp_reg_we,
    input       exmem_mem_re,       // load in MEM stage

    // From MEM/WB pipeline register
    input [4:0] memwb_rd,
    input       memwb_reg_we,
    input       memwb_fp_reg_we,

    // FP register source addresses
    input [4:0] id_fp_rs1_addr,
    input [4:0] id_fp_rs2_addr,
    input [4:0] id_fp_rs3_addr,
    input       id_fp_rs1_used,
    input       id_fp_rs2_used,
    input       id_fp_rs3_used,

    // FPU busy
    input       fpu_busy,

    // Branch / jump
    input       branch_taken,
    input       jalr_taken,

    // Forwarding select outputs (00=regfile, 01=EX/comb, 10=exmem, 11=memwb)
    output reg [1:0] fwd_rs1_sel,
    output reg [1:0] fwd_rs2_sel,
    output reg [1:0] fwd_fp_rs1_sel,
    output reg [1:0] fwd_fp_rs2_sel,
    output reg [1:0] fwd_fp_rs3_sel,

    // Stall / flush outputs
    output stall_if,
    output stall_id,
    output stall_ex,
    output flush_if,
    output flush_id,
    output flush_ex
);

    // ----------------------------------------------------------------
    // Load-use hazard detection
    // ----------------------------------------------------------------
    // Case 1: Load in EX stage (idex) — need to stall 1 cycle so it
    //         reaches MEM, then we can forward from exmem next cycle.
    wire load_use_idex;
    assign load_use_idex = idex_mem_re && (
        (id_rs1_used && (idex_rd == id_rs1_addr) && (idex_rd != 5'd0)) ||
        (id_rs2_used && (idex_rd == id_rs2_addr) && (idex_rd != 5'd0)) ||
        (id_fp_rs1_used && (idex_rd == id_fp_rs1_addr)) ||
        (id_fp_rs2_used && (idex_rd == id_fp_rs2_addr)) ||
        (id_fp_rs3_used && (idex_rd == id_fp_rs3_addr))
    );

    // Case 2: Load in MEM stage (exmem) — stall 1 cycle for mem read.
    wire load_use_exmem;
    assign load_use_exmem = exmem_mem_re && (
        (id_rs1_used && (exmem_rd == id_rs1_addr) && (exmem_rd != 5'd0)) ||
        (id_rs2_used && (exmem_rd == id_rs2_addr) && (exmem_rd != 5'd0)) ||
        (id_fp_rs1_used && (exmem_rd == id_fp_rs1_addr)) ||
        (id_fp_rs2_used && (exmem_rd == id_fp_rs2_addr)) ||
        (id_fp_rs3_used && (exmem_rd == id_fp_rs3_addr))
    );

    wire load_use_hazard = load_use_idex | load_use_exmem;

    // ----------------------------------------------------------------
    // Integer register forwarding
    // Priority: EX (idex, 01) > MEM (exmem, 10) > WB (memwb, 11)
    // 00 = use register file (no forwarding)
    // 01 = forward from EX stage (combinational ALU result)
    // 10 = forward from EX/MEM pipeline register
    // 11 = forward from MEM/WB pipeline register
    // ----------------------------------------------------------------
    always @(*) begin
        fwd_rs1_sel = 2'b00;
        if (idex_reg_we && (idex_rd != 5'd0) && (idex_rd == id_rs1_addr) && id_rs1_used && !idex_mem_re)
            fwd_rs1_sel = 2'b01;
        else if (exmem_reg_we && (exmem_rd != 5'd0) && (exmem_rd == id_rs1_addr) && id_rs1_used)
            fwd_rs1_sel = 2'b10;
        else if (memwb_reg_we && (memwb_rd != 5'd0) && (memwb_rd == id_rs1_addr) && id_rs1_used)
            fwd_rs1_sel = 2'b11;
    end

    always @(*) begin
        fwd_rs2_sel = 2'b00;
        if (idex_reg_we && (idex_rd != 5'd0) && (idex_rd == id_rs2_addr) && id_rs2_used && !idex_mem_re)
            fwd_rs2_sel = 2'b01;
        else if (exmem_reg_we && (exmem_rd != 5'd0) && (exmem_rd == id_rs2_addr) && id_rs2_used)
            fwd_rs2_sel = 2'b10;
        else if (memwb_reg_we && (memwb_rd != 5'd0) && (memwb_rd == id_rs2_addr) && id_rs2_used)
            fwd_rs2_sel = 2'b11;
    end

    // ----------------------------------------------------------------
    // FP register forwarding (f0 is NOT hardwired — no !=0 check)
    // Priority: EX (01) > MEM (10) > WB (11)
    // Note: idex_mem_re check not needed for FP — FP loads go through
    // the integer load path and don't set idex_fp_reg_we until WB.
    // ----------------------------------------------------------------
    always @(*) begin
        fwd_fp_rs1_sel = 2'b00;
        if (idex_fp_reg_we && (idex_rd == id_fp_rs1_addr) && id_fp_rs1_used)
            fwd_fp_rs1_sel = 2'b01;
        else if (exmem_fp_reg_we && (exmem_rd == id_fp_rs1_addr) && id_fp_rs1_used)
            fwd_fp_rs1_sel = 2'b10;
        else if (memwb_fp_reg_we && (memwb_rd == id_fp_rs1_addr) && id_fp_rs1_used)
            fwd_fp_rs1_sel = 2'b11;
    end

    always @(*) begin
        fwd_fp_rs2_sel = 2'b00;
        if (idex_fp_reg_we && (idex_rd == id_fp_rs2_addr) && id_fp_rs2_used)
            fwd_fp_rs2_sel = 2'b01;
        else if (exmem_fp_reg_we && (exmem_rd == id_fp_rs2_addr) && id_fp_rs2_used)
            fwd_fp_rs2_sel = 2'b10;
        else if (memwb_fp_reg_we && (memwb_rd == id_fp_rs2_addr) && id_fp_rs2_used)
            fwd_fp_rs2_sel = 2'b11;
    end

    always @(*) begin
        fwd_fp_rs3_sel = 2'b00;
        if (idex_fp_reg_we && (idex_rd == id_fp_rs3_addr) && id_fp_rs3_used)
            fwd_fp_rs3_sel = 2'b01;
        else if (exmem_fp_reg_we && (exmem_rd == id_fp_rs3_addr) && id_fp_rs3_used)
            fwd_fp_rs3_sel = 2'b10;
        else if (memwb_fp_reg_we && (memwb_rd == id_fp_rs3_addr) && id_fp_rs3_used)
            fwd_fp_rs3_sel = 2'b11;
    end

    // ----------------------------------------------------------------
    // Stall and flush generation
    // ----------------------------------------------------------------
    assign stall_if = load_use_hazard | fpu_busy;
    assign stall_id = load_use_hazard | fpu_busy;
    assign stall_ex = fpu_busy;

    assign flush_if = branch_taken | jalr_taken;
    assign flush_id = branch_taken | jalr_taken;
    assign flush_ex = load_use_hazard;           // insert bubble into EX

endmodule
