// rv16_core.v
// 16-bit 3-stage pipelined RISC-V core (Fetch / Decode / Execute)
// No hardware hazard detection — software must insert NOPs.

module rv16_core (
    input         clk,
    input         rst,

    // Instruction memory interface
    output [7:0]  instr_addr,   // word index into instr_mem (256 entries)
    input  [31:0] instr_data,   // instruction fetched from BRAM

    // Data memory interface
    output [15:0] mem_addr,
    output [15:0] mem_wdata,
    input  [15:0] mem_rdata,
    output        mem_we,
    output        mem_re
);

    // ----------------------------------------------------------------
    // Internal wires
    // ----------------------------------------------------------------

    // Stall / flush
    wire stall = 1'b0;          // no hardware interlock; NOP-padded SW
    wire flush;

    // Fetch -> Decode
    wire [15:0] pc_out;         // current PC (byte address)
    wire [15:0] ifde_pc;        // PC carried into decode stage
    wire        ifde_valid;     // decode-stage valid bit

    // Branch feedback  (Execute -> Fetch)
    wire        branch_taken;
    wire [15:0] branch_target;

    assign flush = branch_taken;

    // Writeback feedback  (Execute -> Decode)
    wire [3:0]  wb_rd;
    wire [15:0] wb_data;
    wire        wb_we;

    // Decode -> Execute  (pipeline register outputs)
    wire [3:0]  deex_alu_op;
    wire [15:0] deex_rs1_data;
    wire [15:0] deex_rs2_data;
    wire [3:0]  deex_rd;
    wire        deex_reg_we;
    wire        deex_mem_we;
    wire        deex_mem_re;
    wire [1:0]  deex_branch_op;
    wire        deex_alu_src;
    wire [1:0]  deex_wb_sel;
    wire [15:0] deex_pc;
    wire [15:0] deex_imm;
    wire        deex_valid;

    // ----------------------------------------------------------------
    // Instruction address  (byte PC -> word index, 8 bits)
    // ----------------------------------------------------------------
    assign instr_addr = pc_out[9:2];

    // ----------------------------------------------------------------
    // Stage 1 — Fetch
    // ----------------------------------------------------------------
    fetch u_fetch (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall),
        .flush          (flush),
        .branch_taken   (branch_taken),
        .branch_target  (branch_target),
        .pc_out         (pc_out),
        .ifde_pc        (ifde_pc),
        .ifde_valid     (ifde_valid)
    );

    // ----------------------------------------------------------------
    // Stage 2 — Decode
    // ----------------------------------------------------------------
    decode u_decode (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall),
        .flush          (flush),
        // From fetch / instruction memory
        .instr          (instr_data),
        .ifde_pc        (ifde_pc),
        .ifde_valid     (ifde_valid),
        // Writeback from execute
        .wb_rd          (wb_rd),
        .wb_data        (wb_data),
        .wb_we          (wb_we),
        // To execute
        .deex_alu_op    (deex_alu_op),
        .deex_rs1_data  (deex_rs1_data),
        .deex_rs2_data  (deex_rs2_data),
        .deex_rd        (deex_rd),
        .deex_reg_we    (deex_reg_we),
        .deex_mem_we    (deex_mem_we),
        .deex_mem_re    (deex_mem_re),
        .deex_branch_op (deex_branch_op),
        .deex_alu_src   (deex_alu_src),
        .deex_wb_sel    (deex_wb_sel),
        .deex_pc        (deex_pc),
        .deex_imm       (deex_imm),
        .deex_valid     (deex_valid)
    );

    // ----------------------------------------------------------------
    // Stage 3 — Execute
    // ----------------------------------------------------------------
    execute u_execute (
        .clk            (clk),
        .rst            (rst),
        // From decode
        .deex_alu_op    (deex_alu_op),
        .deex_rs1_data  (deex_rs1_data),
        .deex_rs2_data  (deex_rs2_data),
        .deex_rd        (deex_rd),
        .deex_reg_we    (deex_reg_we),
        .deex_mem_we    (deex_mem_we),
        .deex_mem_re    (deex_mem_re),
        .deex_branch_op (deex_branch_op),
        .deex_alu_src   (deex_alu_src),
        .deex_wb_sel    (deex_wb_sel),
        .deex_pc        (deex_pc),
        .deex_imm       (deex_imm),
        .deex_valid     (deex_valid),
        // Data memory
        .mem_rdata      (mem_rdata),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_we         (mem_we),
        .mem_re         (mem_re),
        // Branch feedback
        .branch_taken   (branch_taken),
        .branch_target  (branch_target),
        // Writeback
        .wb_rd          (wb_rd),
        .wb_data        (wb_data),
        .wb_we          (wb_we)
    );

endmodule
