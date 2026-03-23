// ============================================================================
// execute.v - Execute (EX) Stage
// RV64IFD 5-Stage Pipeline
// Integer ALU + branch resolution + FPU stub + EX/MEM pipeline register
// Target: Vivado 2020.2
// ============================================================================

module execute (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_ex,
    input  wire        flush_ex,

    // From ID/EX
    input  wire [63:0] idex_rs1_data,
    input  wire [63:0] idex_rs2_data,
    input  wire [63:0] idex_imm,
    input  wire [63:0] idex_pc,
    input  wire [63:0] idex_fp_rs1_data,
    input  wire [63:0] idex_fp_rs2_data,
    input  wire [63:0] idex_fp_rs3_data,
    input  wire [4:0]  idex_rd,
    input  wire [4:0]  idex_alu_op,
    input  wire        idex_alu_src,
    input  wire        idex_alu_a_sel,
    input  wire        idex_reg_we,
    input  wire        idex_fp_reg_we,
    input  wire        idex_mem_we,
    input  wire        idex_mem_re,
    input  wire [3:0]  idex_branch_op,
    input  wire [2:0]  idex_wb_sel,
    input  wire [1:0]  idex_mem_size,
    input  wire        idex_mem_unsigned,
    input  wire        idex_valid,
    input  wire        idex_fp_en,
    input  wire [4:0]  idex_fp_op,
    input  wire [2:0]  idex_fp_rm,
    input  wire        idex_is_fp_load,
    input  wire        idex_is_fp_store,

    // Branch/jump outputs (to fetch)
    output wire        branch_taken,
    output wire [63:0] branch_target,
    output wire        jalr_taken,
    output wire [63:0] jalr_target,

    // FPU status
    output wire        fpu_busy,
    output wire [4:0]  fpu_flags_out,
    output wire        fpu_done,

    // Combinational EX result (for forwarding to decode before latch)
    output wire [63:0] ex_result_comb,
    output wire [63:0] ex_fp_result_comb,

    // EX/MEM pipeline outputs
    output reg  [63:0] exmem_alu_result,
    output reg  [63:0] exmem_rs2_data,
    output reg  [4:0]  exmem_rd,
    output reg         exmem_reg_we,
    output reg         exmem_fp_reg_we,
    output reg         exmem_mem_we,
    output reg         exmem_mem_re,
    output reg  [2:0]  exmem_wb_sel,
    output reg  [1:0]  exmem_mem_size,
    output reg         exmem_mem_unsigned,
    output reg         exmem_valid,
    output reg         exmem_is_fp_load,
    output reg         exmem_is_fp_store
);

    // ========================================================================
    // Constants
    // ========================================================================
    localparam [3:0] BR_NONE = 4'd0, BR_BEQ  = 4'd1, BR_BNE  = 4'd2,
                     BR_JAL  = 4'd3, BR_JALR = 4'd4, BR_BLT  = 4'd5,
                     BR_BGE  = 4'd6, BR_BLTU = 4'd7, BR_BGEU = 4'd8;

    // ========================================================================
    // ALU Input Muxes
    // ========================================================================
    wire [63:0] alu_a = idex_alu_a_sel ? idex_pc : idex_rs1_data;
    wire [63:0] alu_b = idex_alu_src   ? idex_imm : idex_rs2_data;

    // ========================================================================
    // ALU Instance
    // ========================================================================
    wire [63:0] alu_result;

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .alu_op (idex_alu_op),
        .result (alu_result)
    );

    // ========================================================================
    // Branch Comparison (using rs1_data and rs2_data directly)
    // ========================================================================
    wire        zero       = (idex_rs1_data == idex_rs2_data);
    wire        lt_signed  = ($signed(idex_rs1_data) < $signed(idex_rs2_data));
    wire        lt_unsigned = (idex_rs1_data < idex_rs2_data);

    // Branch resolution
    reg  br_take;
    always @(*) begin
        br_take = 1'b0;
        case (idex_branch_op)
            BR_NONE: br_take = 1'b0;
            BR_BEQ:  br_take = zero;
            BR_BNE:  br_take = ~zero;
            BR_JAL:  br_take = 1'b1;
            BR_JALR: br_take = 1'b0; // JALR handled separately
            BR_BLT:  br_take = lt_signed;
            BR_BGE:  br_take = ~lt_signed;
            BR_BLTU: br_take = lt_unsigned;
            BR_BGEU: br_take = ~lt_unsigned;
            default: br_take = 1'b0;
        endcase
    end

    assign branch_taken  = br_take & idex_valid;
    assign branch_target = idex_pc + idex_imm;
    assign jalr_taken    = (idex_branch_op == BR_JALR) & idex_valid;
    assign jalr_target   = (idex_rs1_data + idex_imm) & ~64'd1;

    // ========================================================================
    // PC+4 for JAL/JALR writeback
    // ========================================================================
    wire [63:0] pc_plus_4 = idex_pc + 64'd4;

    // Select ALU result, PC+4, or FPU result for writeback
    wire [63:0] ex_result = idex_fp_en ? fpu_result :
                            (idex_branch_op == BR_JAL || idex_branch_op == BR_JALR)
                            ? pc_plus_4 : alu_result;

    // Combinational forwarding outputs (available before EX/MEM latch)
    assign ex_result_comb    = ex_result;
    assign ex_fp_result_comb = fpu_result;

    // ========================================================================
    // FPU Instance
    // ========================================================================
    wire [63:0] fpu_result;
    wire        fpu_done_w;
    wire        fpu_busy_w;
    wire [4:0]  fpu_flags_w;
    wire        fpu_result_is_int;

    fpu_top u_fpu (
        .clk          (clk),
        .rst          (rst),
        .start        (idex_fp_en & idex_valid & ~stall_ex),
        .fp_op        (idex_fp_op),
        .rm           (idex_fp_rm),
        .fp_a         (idex_fp_rs1_data),
        .fp_b         (idex_fp_rs2_data),
        .fp_c         (idex_fp_rs3_data),
        .int_src      (idex_rs1_data),
        .fp_result    (fpu_result),
        .done         (fpu_done_w),
        .busy         (fpu_busy_w),
        .fp_flags     (fpu_flags_w),
        .result_is_int(fpu_result_is_int)
    );

    assign fpu_busy      = fpu_busy_w;
    assign fpu_flags_out = fpu_flags_w;
    assign fpu_done      = fpu_done_w;

    // ========================================================================
    // Store Data Mux (FP store vs integer store)
    // ========================================================================
    wire [63:0] store_data = idex_is_fp_store ? idex_fp_rs2_data : idex_rs2_data;

    // ========================================================================
    // EX/MEM Pipeline Register
    // ========================================================================
    always @(posedge clk) begin
        if (rst || flush_ex) begin
            exmem_alu_result  <= 64'd0;
            exmem_rs2_data    <= 64'd0;
            exmem_rd          <= 5'd0;
            exmem_reg_we      <= 1'b0;
            exmem_fp_reg_we   <= 1'b0;
            exmem_mem_we      <= 1'b0;
            exmem_mem_re      <= 1'b0;
            exmem_wb_sel      <= 3'd0;
            exmem_mem_size    <= 2'd0;
            exmem_mem_unsigned <= 1'b0;
            exmem_valid       <= 1'b0;
            exmem_is_fp_load  <= 1'b0;
            exmem_is_fp_store <= 1'b0;
        end else if (!stall_ex) begin
            exmem_alu_result  <= ex_result;
            exmem_rs2_data    <= store_data;
            exmem_rd          <= idex_rd;
            exmem_reg_we      <= idex_reg_we;
            exmem_fp_reg_we   <= idex_fp_reg_we;
            exmem_mem_we      <= idex_mem_we;
            exmem_mem_re      <= idex_mem_re;
            exmem_wb_sel      <= idex_wb_sel;
            exmem_mem_size    <= idex_mem_size;
            exmem_mem_unsigned <= idex_mem_unsigned;
            exmem_valid       <= idex_valid;
            exmem_is_fp_load  <= idex_is_fp_load;
            exmem_is_fp_store <= idex_is_fp_store;
        end
        // stall_ex: hold current values
    end

endmodule
