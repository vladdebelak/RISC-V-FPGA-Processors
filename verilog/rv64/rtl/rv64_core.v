// rv64_core.v — RV64I pipeline shell (fetch / decode / execute)
`default_nettype none

module rv64_core (
    input  wire        clk,
    input  wire        rst,
    // Instruction memory
    output wire [8:0]  instr_addr,   // word index for 512-entry instr_mem
    input  wire [31:0] instr_data,
    // Data memory / bus
    output wire [63:0] mem_addr,
    output wire [63:0] mem_wdata,
    input  wire [63:0] mem_rdata,
    output wire        mem_we,
    output wire        mem_re,
    output wire [1:0]  mem_size,
    output wire        mem_unsigned
);

    // ---------------------------------------------------------------
    // Internal wires
    // ---------------------------------------------------------------

    // Fetch outputs
    wire [63:0] pc_out;
    wire [63:0] ifde_pc;
    wire        ifde_valid;

    // Decode outputs  (deex = decode-to-execute pipeline signals)
    wire [63:0] deex_pc;
    wire        deex_valid;
    wire [4:0]  deex_rd;
    wire [63:0] deex_rs1_data;
    wire [63:0] deex_rs2_data;
    wire [63:0] deex_imm;
    wire        deex_alu_src;     // 0=rs2, 1=imm
    wire        deex_alu_a_sel;   // 0=rs1, 1=PC (AUIPC)
    wire [4:0]  deex_alu_op;
    wire        deex_mem_we;
    wire        deex_mem_re;
    wire        deex_reg_we;
    wire [3:0]  deex_branch_op;
    wire [1:0]  deex_wb_sel;
    wire [1:0]  deex_mem_size;
    wire        deex_mem_unsigned;

    // Execute → fetch  (branch / jump resolution)
    wire        branch_taken;
    wire [63:0] branch_target;
    wire        jalr_taken;
    wire [63:0] jalr_target;

    // Execute → decode  (write-back)
    wire [4:0]  wb_rd;
    wire [63:0] wb_data;
    wire        wb_we;

    // Pipeline control
    wire        flush;
    wire        stall;

    assign flush = branch_taken | jalr_taken;
    assign stall = 1'b0;   // NOP padding eliminates hazards

    // Instruction address = PC word index (bits [10:2])
    assign instr_addr = pc_out[10:2];

    // ---------------------------------------------------------------
    // Fetch stage
    // ---------------------------------------------------------------
    fetch u_fetch (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall),
        .flush         (flush),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .jalr_taken    (jalr_taken),
        .jalr_target   (jalr_target),
        .pc_out        (pc_out),
        .ifde_pc       (ifde_pc),
        .ifde_valid    (ifde_valid)
    );

    // ---------------------------------------------------------------
    // Decode stage
    // ---------------------------------------------------------------
    decode u_decode (
        .clk             (clk),
        .rst             (rst),
        .stall           (stall),
        .flush           (flush),
        // from fetch
        .instr           (instr_data),
        .ifde_pc         (ifde_pc),
        .ifde_valid      (ifde_valid),
        // write-back from execute
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        .wb_we           (wb_we),
        // outputs to execute
        .deex_pc         (deex_pc),
        .deex_valid      (deex_valid),
        .deex_rd         (deex_rd),
        .deex_rs1_data   (deex_rs1_data),
        .deex_rs2_data   (deex_rs2_data),
        .deex_imm        (deex_imm),
        .deex_alu_src    (deex_alu_src),
        .deex_alu_a_sel  (deex_alu_a_sel),
        .deex_alu_op     (deex_alu_op),
        .deex_mem_we     (deex_mem_we),
        .deex_mem_re     (deex_mem_re),
        .deex_reg_we     (deex_reg_we),
        .deex_branch_op  (deex_branch_op),
        .deex_wb_sel     (deex_wb_sel),
        .deex_mem_size   (deex_mem_size),
        .deex_mem_unsigned(deex_mem_unsigned)
    );

    // ---------------------------------------------------------------
    // Execute stage
    // ---------------------------------------------------------------
    execute u_execute (
        .clk             (clk),
        .rst             (rst),
        // from decode
        .deex_pc         (deex_pc),
        .deex_valid      (deex_valid),
        .deex_rd         (deex_rd),
        .deex_rs1_data   (deex_rs1_data),
        .deex_rs2_data   (deex_rs2_data),
        .deex_imm        (deex_imm),
        .deex_alu_src    (deex_alu_src),
        .deex_alu_a_sel  (deex_alu_a_sel),
        .deex_alu_op     (deex_alu_op),
        .deex_mem_we     (deex_mem_we),
        .deex_mem_re     (deex_mem_re),
        .deex_reg_we     (deex_reg_we),
        .deex_branch_op  (deex_branch_op),
        .deex_wb_sel     (deex_wb_sel),
        .deex_mem_size   (deex_mem_size),
        .deex_mem_unsigned(deex_mem_unsigned),
        // data memory interface
        .mem_rdata       (mem_rdata),
        .mem_addr        (mem_addr),
        .mem_wdata       (mem_wdata),
        .mem_we          (mem_we),
        .mem_re          (mem_re),
        .mem_size        (mem_size),
        .mem_unsigned    (mem_unsigned),
        // branch / jump resolution -> fetch
        .branch_taken    (branch_taken),
        .branch_target   (branch_target),
        .jalr_taken      (jalr_taken),
        .jalr_target     (jalr_target),
        // write-back -> decode
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        .wb_we           (wb_we)
    );

endmodule
