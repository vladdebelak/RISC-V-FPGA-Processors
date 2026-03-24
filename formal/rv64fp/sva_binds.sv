`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Bind statements for RV64FP SVA formal verification
//
// Clocking strategy for combinational modules (alu, hazard_unit):
//   These modules have no clock port, so we bind the SVA checker at the
//   parent module level and use hierarchical references to reach the
//   submodule's signals.
//////////////////////////////////////////////////////////////////////////////

// =========================================================================
// 1. Reset synchronizer — has its own clock
// =========================================================================
bind reset_sync sva_reset_sync_props rst_props_i (
    .clk      (clk),
    .rst_btn  (rst_btn),
    .rst_sync (rst_sync),
    .sync_ff0 (sync_ff0),
    .sync_ff1 (sync_ff1)
);

// =========================================================================
// 2. FPU protocol properties — fpu_top has its own clock
// =========================================================================
bind fpu_top sva_fpu_protocol_props fpu_proto_i (
    .clk         (clk),
    .rst         (rst),
    .start       (start),
    .fp_op       (fp_op),
    .rm          (rm),
    .fp_a        (fp_a),
    .fp_b        (fp_b),
    .fp_c        (fp_c),
    .int_src     (int_src),
    .fp_result   (fp_result),
    .done        (done),
    .busy        (busy),
    .fp_flags    (fp_flags),
    .result_is_int(result_is_int)
);

// =========================================================================
// 3. FPU IEEE 754 properties — fpu_top has its own clock
// =========================================================================
bind fpu_top sva_fpu_ieee754_props fpu_ieee_i (
    .clk         (clk),
    .rst         (rst),
    .start       (start),
    .fp_op       (fp_op),
    .rm          (rm),
    .fp_a        (fp_a),
    .fp_b        (fp_b),
    .fp_c        (fp_c),
    .int_src     (int_src),
    .fp_result   (fp_result),
    .done        (done),
    .busy        (busy),
    .fp_flags    (fp_flags),
    .result_is_int(result_is_int)
);

// =========================================================================
// 4. ALU properties — combinational module, bound inside execute which
//    has a clock. ALU instance is u_alu inside execute.
// =========================================================================
bind execute sva_rv64_alu_props alu_props_i (
    .clk         (clk),
    .a           (u_alu.a),
    .b           (u_alu.b),
    .alu_op      (u_alu.alu_op),
    .result      (u_alu.result),
    .zero        (u_alu.zero),
    .lt_signed   (u_alu.lt_signed),
    .lt_unsigned (u_alu.lt_unsigned)
);

// =========================================================================
// 5. Hazard unit properties — combinational module, bound inside
//    rv64fp_core. Hazard unit instance is u_hazard inside rv64fp_core.
// =========================================================================
bind rv64fp_core sva_hazard_unit_props haz_props_i (
    .clk             (clk),
    .id_rs1_addr     (u_hazard.id_rs1_addr),
    .id_rs2_addr     (u_hazard.id_rs2_addr),
    .id_rs1_used     (u_hazard.id_rs1_used),
    .id_rs2_used     (u_hazard.id_rs2_used),
    .idex_rd         (u_hazard.idex_rd),
    .idex_reg_we     (u_hazard.idex_reg_we),
    .idex_fp_reg_we  (u_hazard.idex_fp_reg_we),
    .idex_mem_re     (u_hazard.idex_mem_re),
    .exmem_rd        (u_hazard.exmem_rd),
    .exmem_reg_we    (u_hazard.exmem_reg_we),
    .exmem_fp_reg_we (u_hazard.exmem_fp_reg_we),
    .exmem_mem_re    (u_hazard.exmem_mem_re),
    .memwb_rd        (u_hazard.memwb_rd),
    .memwb_reg_we    (u_hazard.memwb_reg_we),
    .memwb_fp_reg_we (u_hazard.memwb_fp_reg_we),
    .id_fp_rs1_addr  (u_hazard.id_fp_rs1_addr),
    .id_fp_rs2_addr  (u_hazard.id_fp_rs2_addr),
    .id_fp_rs3_addr  (u_hazard.id_fp_rs3_addr),
    .id_fp_rs1_used  (u_hazard.id_fp_rs1_used),
    .id_fp_rs2_used  (u_hazard.id_fp_rs2_used),
    .id_fp_rs3_used  (u_hazard.id_fp_rs3_used),
    .fpu_busy        (u_hazard.fpu_busy),
    .branch_taken    (u_hazard.branch_taken),
    .jalr_taken      (u_hazard.jalr_taken),
    .fwd_rs1_sel     (u_hazard.fwd_rs1_sel),
    .fwd_rs2_sel     (u_hazard.fwd_rs2_sel),
    .fwd_fp_rs1_sel  (u_hazard.fwd_fp_rs1_sel),
    .fwd_fp_rs2_sel  (u_hazard.fwd_fp_rs2_sel),
    .fwd_fp_rs3_sel  (u_hazard.fwd_fp_rs3_sel),
    .stall_if        (u_hazard.stall_if),
    .stall_id        (u_hazard.stall_id),
    .stall_ex        (u_hazard.stall_ex),
    .flush_if        (u_hazard.flush_if),
    .flush_id        (u_hazard.flush_id),
    .flush_ex        (u_hazard.flush_ex)
);

// =========================================================================
// 6. Memory bus properties — has its own clock
// =========================================================================
bind mem_bus sva_mem_bus_props mbus_props_i (
    .clk         (clk),
    .rst         (rst),
    .addr        (addr),
    .wdata       (wdata),
    .we          (we),
    .re          (re),
    .size        (size),
    .is_unsigned (is_unsigned),
    .dm_addr     (dm_addr),
    .dm_wdata    (dm_wdata),
    .dm_rdata    (dm_rdata),
    .dm_we       (dm_we),
    .dm_byte_en  (dm_byte_en),
    .gpio_we     (gpio_we),
    .gpio_wdata  (gpio_wdata),
    .gpio_rdata  (gpio_rdata),
    .rdata       (rdata)
);

// =========================================================================
// 7. Core pipeline properties — has its own clock
// =========================================================================
bind rv64fp_core sva_rv64fp_pipeline_props core_props_i (
    .clk          (clk),
    .rst          (rst),
    .instr_addr   (instr_addr),
    .instr_data   (instr_data),
    .mem_addr     (mem_addr),
    .mem_wdata    (mem_wdata),
    .mem_rdata    (mem_rdata),
    .mem_we       (mem_we),
    .mem_re       (mem_re),
    .mem_size     (mem_size),
    .mem_unsigned (mem_unsigned)
);
