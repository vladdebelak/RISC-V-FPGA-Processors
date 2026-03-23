// ============================================================================
// writeback.v - Writeback (WB) Stage
// RV64IFD 5-Stage Pipeline
// Writeback mux + register write routing
// Target: Vivado 2020.2
// ============================================================================

module writeback (
    // From MEM/WB
    input  wire [63:0] memwb_alu_result,
    input  wire [63:0] memwb_mem_rdata,
    input  wire [4:0]  memwb_rd,
    input  wire        memwb_reg_we,
    input  wire        memwb_fp_reg_we,
    input  wire [2:0]  memwb_wb_sel,
    input  wire        memwb_valid,
    input  wire        memwb_is_fp_load,

    // Outputs to register files (in decode)
    output wire [4:0]  wb_rd,
    output wire [63:0] wb_data,
    output wire        wb_reg_we,
    output wire        wb_fp_reg_we,
    output wire [63:0] wb_fp_data
);

    // ========================================================================
    // Constants
    // ========================================================================
    localparam [2:0] WB_ALU = 3'd0, WB_MEM = 3'd1, WB_PC4 = 3'd2, WB_FPU = 3'd3;

    // ========================================================================
    // Writeback Mux (combinational)
    // ========================================================================
    reg [63:0] wb_data_mux;

    always @(*) begin
        case (memwb_wb_sel)
            WB_ALU:  wb_data_mux = memwb_alu_result;
            WB_MEM:  wb_data_mux = memwb_mem_rdata;
            WB_PC4:  wb_data_mux = memwb_alu_result; // PC+4 was computed in EX
            WB_FPU:  wb_data_mux = memwb_alu_result; // FPU result stored as alu_result
            default: wb_data_mux = memwb_alu_result;
        endcase
    end

    // ========================================================================
    // Output Assignments
    // ========================================================================
    assign wb_rd       = memwb_rd;
    assign wb_data     = wb_data_mux;
    assign wb_reg_we   = memwb_reg_we & memwb_valid;
    assign wb_fp_reg_we = (memwb_fp_reg_we | memwb_is_fp_load) & memwb_valid;
    assign wb_fp_data  = memwb_is_fp_load ? memwb_mem_rdata : memwb_alu_result;

endmodule
