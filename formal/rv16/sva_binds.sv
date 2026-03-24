`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Bind statements for RV16 SVA formal verification
//////////////////////////////////////////////////////////////////////////////

// Bind reset synchronizer properties
bind reset_sync sva_reset_sync_props rst_props_i (
    .clk      (clk),
    .rst_btn  (rst_btn),
    .rst_sync (rst_sync),
    .sync_ff0 (sync_ff0),
    .sync_ff1 (sync_ff1)
);

// Bind ALU properties (combinational module — clock from parent)
bind alu sva_rv16_alu_props alu_props_i (
    .clk    (rv16_top.CLK100MHZ),
    .a      (a),
    .b      (b),
    .alu_op (alu_op),
    .result (result),
    .zero   (zero)
);

// Bind core properties
bind rv16_core sva_rv16_core_props core_props_i (
    .clk        (clk),
    .rst        (rst),
    .instr_addr (instr_addr),
    .instr_data (instr_data),
    .mem_addr   (mem_addr),
    .mem_wdata  (mem_wdata),
    .mem_rdata  (mem_rdata),
    .mem_we     (mem_we)
);
