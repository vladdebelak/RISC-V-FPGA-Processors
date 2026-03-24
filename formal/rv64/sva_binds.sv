`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Bind statements for RV64 SVA formal verification
//////////////////////////////////////////////////////////////////////////////

// Bind reset synchronizer properties
bind reset_sync sva_reset_sync_props rst_props_i (
    .clk      (clk),
    .rst_btn  (rst_btn),
    .rst_sync (rst_sync),
    .sync_ff0 (sync_ff0),
    .sync_ff1 (sync_ff1)
);

// Bind core properties
bind rv64_core sva_rv64_core_props core_props_i (
    .clk        (clk),
    .rst        (rst),
    .instr_addr (instr_addr),
    .instr_data (instr_data),
    .mem_addr   (mem_addr),
    .mem_wdata  (mem_wdata),
    .mem_rdata  (mem_rdata),
    .mem_we     (mem_we)
);
