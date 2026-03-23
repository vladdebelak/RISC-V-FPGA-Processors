`timescale 1ns / 1ps

module rv64fp_core (
    input  wire        clk,
    input  wire        rst,
    // Instruction memory interface
    output wire [8:0]  instr_addr,
    input  wire [31:0] instr_data,
    // Data memory interface
    output wire [63:0] mem_addr,
    output wire [63:0] mem_wdata,
    input  wire [63:0] mem_rdata,
    output wire        mem_we,
    output wire        mem_re,
    output wire [1:0]  mem_size,
    output wire        mem_unsigned
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // --- Fetch stage outputs ---
    wire [63:0] pc_out;
    wire [63:0] ifid_pc;
    wire        ifid_valid;

    // Instruction address to BRAM (word-aligned)
    assign instr_addr = pc_out[10:2];

    // --- Decode stage outputs ---
    wire [4:0]  id_rs1_addr;
    wire [4:0]  id_rs2_addr;
    wire        id_rs1_used;
    wire        id_rs2_used;
    wire [4:0]  id_fp_rs1_addr;
    wire [4:0]  id_fp_rs2_addr;
    wire [4:0]  id_fp_rs3_addr;
    wire        id_fp_rs1_used;
    wire        id_fp_rs2_used;
    wire        id_fp_rs3_used;

    wire [63:0] idex_pc;
    wire [63:0] idex_rs1_data;
    wire [63:0] idex_rs2_data;
    wire [63:0] idex_imm;
    wire [4:0]  idex_rd;
    wire [4:0]  idex_alu_op;
    wire        idex_alu_src;       // 0=rs2, 1=imm
    wire        idex_alu_a_sel;     // 0=rs1, 1=PC
    wire        idex_reg_we;
    wire        idex_mem_re;
    wire        idex_mem_we;
    wire [1:0]  idex_mem_size;
    wire        idex_mem_unsigned;
    wire [3:0]  idex_branch_op;
    wire [2:0]  idex_wb_sel;
    wire        idex_valid;
    // FPU signals
    wire        idex_fp_reg_we;
    wire        idex_fp_en;
    wire [4:0]  idex_fp_op;
    wire [2:0]  idex_fp_rm;
    wire [63:0] idex_fp_rs1_data;
    wire [63:0] idex_fp_rs2_data;
    wire [63:0] idex_fp_rs3_data;
    wire        idex_is_fp_load;
    wire        idex_is_fp_store;

    // --- Execute stage outputs ---
    wire        ex_branch_taken;
    wire [63:0] ex_branch_target;
    wire        ex_jalr_taken;
    wire [63:0] ex_jalr_target;

    wire [4:0]  exmem_rd;
    wire [63:0] exmem_alu_result;
    wire [63:0] exmem_rs2_data;
    wire        exmem_reg_we;
    wire        exmem_mem_re;
    wire        exmem_mem_we;
    wire [2:0]  exmem_wb_sel;
    wire [1:0]  exmem_mem_size;
    wire        exmem_mem_unsigned;
    wire        exmem_valid;
    wire        exmem_fp_reg_we;
    wire        exmem_is_fp_load;
    wire        exmem_is_fp_store;
    wire        fpu_busy;
    wire [4:0]  fpu_flags;
    wire        fpu_done;

    // --- FCSR wires ---
    wire [2:0]  fcsr_frm;
    wire [4:0]  fcsr_fflags;

    // --- Memory stage outputs ---
    wire [4:0]  memwb_rd;
    wire [63:0] memwb_alu_result;
    wire [63:0] memwb_mem_rdata;
    wire        memwb_reg_we;
    wire        memwb_fp_reg_we;
    wire [2:0]  memwb_wb_sel;
    wire        memwb_valid;
    wire        memwb_is_fp_load;

    // --- Writeback stage outputs ---
    wire [4:0]  wb_rd;
    wire [63:0] wb_data;
    wire        wb_reg_we;
    wire        wb_fp_reg_we;
    wire [63:0] wb_fp_data;

    // --- Hazard unit outputs ---
    wire [1:0]  fwd_rs1_sel;
    wire [1:0]  fwd_rs2_sel;
    wire [1:0]  fwd_fp_rs1_sel;
    wire [1:0]  fwd_fp_rs2_sel;
    wire [1:0]  fwd_fp_rs3_sel;
    wire        stall_if;
    wire        stall_id;
    wire        stall_ex;
    wire        flush_if;
    wire        flush_id;
    wire        flush_ex;

    // --- Combinational EX results (for 1-cycle-ahead forwarding) ---
    wire [63:0] ex_result_comb;
    wire [63:0] ex_fp_result_comb;

    // --- Forwarded result wires ---
    wire [63:0] exmem_result;
    wire [63:0] memwb_result;
    wire [63:0] exmem_fp_result_fwd;
    wire [63:0] memwb_fp_result_fwd;

    assign exmem_result        = exmem_alu_result;
    assign memwb_result        = wb_data;
    assign exmem_fp_result_fwd = exmem_alu_result;   // Phase 2: replace with FP result
    assign memwb_fp_result_fwd = wb_fp_data;

    // =========================================================================
    // Stage instantiations
    // =========================================================================

    fetch u_fetch (
        .clk            (clk),
        .rst            (rst),
        .stall_if       (stall_if),
        .flush_if       (flush_if),
        .branch_taken   (ex_branch_taken),
        .branch_target  (ex_branch_target),
        .jalr_taken     (ex_jalr_taken),
        .jalr_target    (ex_jalr_target),
        .pc_out         (pc_out),
        .ifid_pc        (ifid_pc),
        .ifid_valid     (ifid_valid)
    );

    decode u_decode (
        .clk            (clk),
        .rst            (rst),
        .stall_id       (stall_id),
        .flush_id       (flush_id),
        // FCSR rounding mode
        .fcsr_frm       (fcsr_frm),
        // From fetch / instruction memory
        .instr          (instr_data),
        .ifid_pc        (ifid_pc),
        .ifid_valid     (ifid_valid),
        // Writeback
        .wb_rd          (wb_rd),
        .wb_data        (wb_data),
        .wb_reg_we      (wb_reg_we),
        .wb_fp_reg_we   (wb_fp_reg_we),
        .wb_fp_data     (wb_fp_data),
        // Forwarding mux selects
        .fwd_rs1_sel    (fwd_rs1_sel),
        .fwd_rs2_sel    (fwd_rs2_sel),
        .fwd_fp_rs1_sel (fwd_fp_rs1_sel),
        .fwd_fp_rs2_sel (fwd_fp_rs2_sel),
        .fwd_fp_rs3_sel (fwd_fp_rs3_sel),
        // Forwarded data
        .ex_result      (ex_result_comb),
        .exmem_result   (exmem_result),
        .memwb_result   (memwb_result),
        .ex_fp_result   (ex_fp_result_comb),
        .exmem_fp_result(exmem_fp_result_fwd),
        .memwb_fp_result(memwb_fp_result_fwd),
        // Outputs to hazard unit
        .id_rs1_addr    (id_rs1_addr),
        .id_rs2_addr    (id_rs2_addr),
        .id_rs1_used    (id_rs1_used),
        .id_rs2_used    (id_rs2_used),
        .id_fp_rs1_addr (id_fp_rs1_addr),
        .id_fp_rs2_addr (id_fp_rs2_addr),
        .id_fp_rs3_addr (id_fp_rs3_addr),
        .id_fp_rs1_used (id_fp_rs1_used),
        .id_fp_rs2_used (id_fp_rs2_used),
        .id_fp_rs3_used (id_fp_rs3_used),
        // Pipeline register outputs (ID/EX)
        .idex_pc        (idex_pc),
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .idex_imm       (idex_imm),
        .idex_rd        (idex_rd),
        .idex_alu_op    (idex_alu_op),
        .idex_alu_src   (idex_alu_src),
        .idex_alu_a_sel (idex_alu_a_sel),
        .idex_reg_we    (idex_reg_we),
        .idex_mem_re    (idex_mem_re),
        .idex_mem_we    (idex_mem_we),
        .idex_mem_size  (idex_mem_size),
        .idex_mem_unsigned(idex_mem_unsigned),
        .idex_branch_op (idex_branch_op),
        .idex_wb_sel    (idex_wb_sel),
        .idex_valid     (idex_valid),
        // FPU signals
        .idex_fp_reg_we (idex_fp_reg_we),
        .idex_fp_en     (idex_fp_en),
        .idex_fp_op     (idex_fp_op),
        .idex_fp_rm     (idex_fp_rm),
        .idex_fp_rs1_data(idex_fp_rs1_data),
        .idex_fp_rs2_data(idex_fp_rs2_data),
        .idex_fp_rs3_data(idex_fp_rs3_data),
        .idex_is_fp_load (idex_is_fp_load),
        .idex_is_fp_store(idex_is_fp_store)
    );

    execute u_execute (
        .clk            (clk),
        .rst            (rst),
        .stall_ex       (stall_ex),
        .flush_ex       (flush_ex),
        // ID/EX inputs
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .idex_imm       (idex_imm),
        .idex_pc        (idex_pc),
        .idex_fp_rs1_data(idex_fp_rs1_data),
        .idex_fp_rs2_data(idex_fp_rs2_data),
        .idex_fp_rs3_data(idex_fp_rs3_data),
        .idex_rd        (idex_rd),
        .idex_alu_op    (idex_alu_op),
        .idex_alu_src   (idex_alu_src),
        .idex_alu_a_sel (idex_alu_a_sel),
        .idex_reg_we    (idex_reg_we),
        .idex_fp_reg_we (idex_fp_reg_we),
        .idex_mem_we    (idex_mem_we),
        .idex_mem_re    (idex_mem_re),
        .idex_branch_op (idex_branch_op),
        .idex_wb_sel    (idex_wb_sel),
        .idex_mem_size  (idex_mem_size),
        .idex_mem_unsigned(idex_mem_unsigned),
        .idex_valid     (idex_valid),
        .idex_fp_en     (idex_fp_en),
        .idex_fp_op     (idex_fp_op),
        .idex_fp_rm     (idex_fp_rm),
        .idex_is_fp_load (idex_is_fp_load),
        .idex_is_fp_store(idex_is_fp_store),
        // Branch/jump outputs to fetch
        .branch_taken   (ex_branch_taken),
        .branch_target  (ex_branch_target),
        .jalr_taken     (ex_jalr_taken),
        .jalr_target    (ex_jalr_target),
        // FPU status
        .fpu_busy       (fpu_busy),
        .fpu_flags_out  (fpu_flags),
        .fpu_done       (fpu_done),
        // Combinational EX results for forwarding
        .ex_result_comb (ex_result_comb),
        .ex_fp_result_comb(ex_fp_result_comb),
        // EX/MEM pipeline outputs
        .exmem_rd       (exmem_rd),
        .exmem_alu_result(exmem_alu_result),
        .exmem_rs2_data (exmem_rs2_data),
        .exmem_reg_we   (exmem_reg_we),
        .exmem_fp_reg_we(exmem_fp_reg_we),
        .exmem_mem_we   (exmem_mem_we),
        .exmem_mem_re   (exmem_mem_re),
        .exmem_wb_sel   (exmem_wb_sel),
        .exmem_mem_size (exmem_mem_size),
        .exmem_mem_unsigned(exmem_mem_unsigned),
        .exmem_valid    (exmem_valid),
        .exmem_is_fp_load (exmem_is_fp_load),
        .exmem_is_fp_store(exmem_is_fp_store)
    );

    memory u_memory (
        .clk            (clk),
        .rst            (rst),
        // EX/MEM inputs
        .exmem_rd       (exmem_rd),
        .exmem_alu_result(exmem_alu_result),
        .exmem_rs2_data (exmem_rs2_data),
        .exmem_reg_we   (exmem_reg_we),
        .exmem_fp_reg_we(exmem_fp_reg_we),
        .exmem_mem_we   (exmem_mem_we),
        .exmem_mem_re   (exmem_mem_re),
        .exmem_wb_sel   (exmem_wb_sel),
        .exmem_mem_size (exmem_mem_size),
        .exmem_mem_unsigned(exmem_mem_unsigned),
        .exmem_valid    (exmem_valid),
        .exmem_is_fp_load (exmem_is_fp_load),
        .exmem_is_fp_store(exmem_is_fp_store),
        // Data memory interface
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_rdata      (mem_rdata),
        .mem_we         (mem_we),
        .mem_re         (mem_re),
        .mem_size       (mem_size),
        .mem_unsigned   (mem_unsigned),
        // MEM/WB pipeline outputs
        .memwb_rd       (memwb_rd),
        .memwb_alu_result(memwb_alu_result),
        .memwb_mem_rdata(memwb_mem_rdata),
        .memwb_reg_we   (memwb_reg_we),
        .memwb_fp_reg_we(memwb_fp_reg_we),
        .memwb_wb_sel   (memwb_wb_sel),
        .memwb_valid    (memwb_valid),
        .memwb_is_fp_load(memwb_is_fp_load)
    );

    writeback u_writeback (
        .memwb_alu_result(memwb_alu_result),
        .memwb_mem_rdata(memwb_mem_rdata),
        .memwb_rd       (memwb_rd),
        .memwb_reg_we   (memwb_reg_we),
        .memwb_fp_reg_we(memwb_fp_reg_we),
        .memwb_wb_sel   (memwb_wb_sel),
        .memwb_valid    (memwb_valid),
        .memwb_is_fp_load(memwb_is_fp_load),
        // Outputs
        .wb_rd          (wb_rd),
        .wb_data        (wb_data),
        .wb_reg_we      (wb_reg_we),
        .wb_fp_reg_we   (wb_fp_reg_we),
        .wb_fp_data     (wb_fp_data)
    );

    fcsr u_fcsr (
        .clk        (clk),
        .rst        (rst),
        .we         (1'b0),           // CSR write not implemented yet
        .wr_frm     (3'b000),
        .wr_fflags  (5'b00000),
        .we_flags   (fpu_done),       // accumulate flags when FPU completes
        .fpu_flags  (fpu_flags),
        .frm        (fcsr_frm),
        .fflags     (fcsr_fflags)
    );

    hazard_unit u_hazard (
        // From decode (integer)
        .id_rs1_addr    (id_rs1_addr),
        .id_rs2_addr    (id_rs2_addr),
        .id_rs1_used    (id_rs1_used),
        .id_rs2_used    (id_rs2_used),
        // From ID/EX (instruction in EX stage)
        .idex_rd        (idex_rd),
        .idex_reg_we    (idex_reg_we),
        .idex_fp_reg_we (idex_fp_reg_we),
        .idex_mem_re    (idex_mem_re),
        // From EX/MEM
        .exmem_rd       (exmem_rd),
        .exmem_reg_we   (exmem_reg_we),
        .exmem_fp_reg_we(exmem_fp_reg_we),
        .exmem_mem_re   (exmem_mem_re),
        // From MEM/WB
        .memwb_rd       (memwb_rd),
        .memwb_reg_we   (memwb_reg_we),
        .memwb_fp_reg_we(memwb_fp_reg_we),
        // FP source addresses from decode
        .id_fp_rs1_addr (id_fp_rs1_addr),
        .id_fp_rs2_addr (id_fp_rs2_addr),
        .id_fp_rs3_addr (id_fp_rs3_addr),
        .id_fp_rs1_used (id_fp_rs1_used),
        .id_fp_rs2_used (id_fp_rs2_used),
        .id_fp_rs3_used (id_fp_rs3_used),
        // FPU busy
        .fpu_busy       (fpu_busy),
        // Branch / jump
        .branch_taken   (ex_branch_taken),
        .jalr_taken     (ex_jalr_taken),
        // Forwarding outputs
        .fwd_rs1_sel    (fwd_rs1_sel),
        .fwd_rs2_sel    (fwd_rs2_sel),
        .fwd_fp_rs1_sel (fwd_fp_rs1_sel),
        .fwd_fp_rs2_sel (fwd_fp_rs2_sel),
        .fwd_fp_rs3_sel (fwd_fp_rs3_sel),
        // Stall / flush
        .stall_if       (stall_if),
        .stall_id       (stall_id),
        .stall_ex       (stall_ex),
        .flush_if       (flush_if),
        .flush_id       (flush_id),
        .flush_ex       (flush_ex)
    );

endmodule
