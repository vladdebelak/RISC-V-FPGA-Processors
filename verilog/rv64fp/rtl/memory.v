// ============================================================================
// memory.v - Memory Access (MEM) Stage
// RV64IFD 5-Stage Pipeline
// Memory interface + MEM/WB pipeline register
// Target: Vivado 2020.2
// ============================================================================

module memory (
    input  wire        clk,
    input  wire        rst,

    // From EX/MEM
    input  wire [63:0] exmem_alu_result,
    input  wire [63:0] exmem_rs2_data,
    input  wire [4:0]  exmem_rd,
    input  wire        exmem_reg_we,
    input  wire        exmem_fp_reg_we,
    input  wire        exmem_mem_we,
    input  wire        exmem_mem_re,
    input  wire [2:0]  exmem_wb_sel,
    input  wire [1:0]  exmem_mem_size,
    input  wire        exmem_mem_unsigned,
    input  wire        exmem_valid,
    input  wire        exmem_is_fp_load,
    input  wire        exmem_is_fp_store,

    // Memory interface (to mem_bus)
    output wire [63:0] mem_addr,
    output wire [63:0] mem_wdata,
    input  wire [63:0] mem_rdata,
    output wire        mem_we,
    output wire        mem_re,
    output wire [1:0]  mem_size,
    output wire        mem_unsigned,

    // MEM/WB pipeline outputs
    output reg  [63:0] memwb_alu_result,
    output reg  [63:0] memwb_mem_rdata,
    output reg  [4:0]  memwb_rd,
    output reg         memwb_reg_we,
    output reg         memwb_fp_reg_we,
    output reg  [2:0]  memwb_wb_sel,
    output reg         memwb_valid,
    output reg         memwb_is_fp_load
);

    // ========================================================================
    // Memory Interface
    // ========================================================================
    assign mem_addr     = exmem_alu_result;
    assign mem_wdata    = exmem_rs2_data;
    assign mem_we       = exmem_mem_we & exmem_valid;
    assign mem_re       = exmem_mem_re & exmem_valid;
    assign mem_size     = exmem_mem_size;
    assign mem_unsigned = exmem_mem_unsigned;

    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            memwb_alu_result <= 64'd0;
            memwb_mem_rdata  <= 64'd0;
            memwb_rd         <= 5'd0;
            memwb_reg_we     <= 1'b0;
            memwb_fp_reg_we  <= 1'b0;
            memwb_wb_sel     <= 3'd0;
            memwb_valid      <= 1'b0;
            memwb_is_fp_load <= 1'b0;
        end else begin
            memwb_alu_result <= exmem_alu_result;
            memwb_mem_rdata  <= mem_rdata;
            memwb_rd         <= exmem_rd;
            memwb_reg_we     <= exmem_reg_we;
            memwb_fp_reg_we  <= exmem_fp_reg_we;
            memwb_wb_sel     <= exmem_wb_sel;
            memwb_valid      <= exmem_valid;
            memwb_is_fp_load <= exmem_is_fp_load;
        end
    end

endmodule
