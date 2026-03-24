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

// Bind ALU properties (combinational module — clock from parent)
bind alu sva_rv64_alu_props alu_props_i (
    .clk         (rv64_top.clk),
    .a           (a),
    .b           (b),
    .alu_op      (alu_op),
    .result      (result),
    .zero        (zero),
    .lt_signed   (lt_signed),
    .lt_unsigned (lt_unsigned)
);

// Bind core properties
bind rv64_core sva_rv64_core_props core_props_i (
    .clk        (clk),
    .rst        (rst),
    .instr_addr (instr_addr),
    .instr_data (instr_data),
    .data_addr  (data_addr),
    .data_wdata (data_wdata),
    .data_rdata (data_rdata),
    .data_we    (data_we)
);
