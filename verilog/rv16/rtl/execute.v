// execute.v — Stage 3: ALU, branch resolution, memory interface, writeback
// 16-bit 3-stage RISC-V microcontroller

module execute (
    input  wire        clk,
    input  wire        rst,
    // From DE/EX pipeline register
    input  wire [15:0] deex_rs1_data,
    input  wire [15:0] deex_rs2_data,
    input  wire [15:0] deex_imm,
    input  wire [15:0] deex_pc,
    input  wire [3:0]  deex_rd,
    input  wire [3:0]  deex_alu_op,
    input  wire        deex_alu_src,
    input  wire        deex_reg_we,
    input  wire        deex_mem_we,
    input  wire        deex_mem_re,
    input  wire [1:0]  deex_branch_op,
    input  wire [1:0]  deex_wb_sel,
    input  wire        deex_valid,
    // Memory interface
    output wire [15:0] mem_addr,
    output wire [15:0] mem_wdata,
    input  wire [15:0] mem_rdata,
    output wire        mem_we,
    output wire        mem_re,
    // Branch output (to fetch stage)
    output wire        branch_taken,
    output wire [15:0] branch_target,
    // Writeback output (to decode regfile)
    output wire [3:0]  wb_rd,
    output wire [15:0] wb_data,
    output wire        wb_we
);

    // ---------------------------------------------------------------
    // Localparams
    // ---------------------------------------------------------------
    localparam BR_NONE = 2'd0;
    localparam BR_BEQ  = 2'd1;
    localparam BR_BNE  = 2'd2;
    localparam BR_JAL  = 2'd3;

    localparam WB_ALU = 2'd0;
    localparam WB_MEM = 2'd1;
    localparam WB_PC4 = 2'd2;

    // ---------------------------------------------------------------
    // ALU instance
    // ---------------------------------------------------------------
    wire [15:0] alu_b = deex_alu_src ? deex_imm : deex_rs2_data;
    wire [15:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .a      (deex_rs1_data),
        .b      (alu_b),
        .alu_op (deex_alu_op),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // ---------------------------------------------------------------
    // Branch resolution (combinational)
    // ---------------------------------------------------------------
    assign branch_target = deex_pc + deex_imm;

    reg branch_taken_r;
    always @(*) begin
        branch_taken_r = 1'b0;
        if (deex_valid) begin
            case (deex_branch_op)
                BR_JAL:  branch_taken_r = 1'b1;
                BR_BEQ:  branch_taken_r = alu_zero;
                BR_BNE:  branch_taken_r = ~alu_zero;
                default: branch_taken_r = 1'b0;
            endcase
        end
    end
    assign branch_taken = branch_taken_r;

    // ---------------------------------------------------------------
    // Memory interface
    // ---------------------------------------------------------------
    assign mem_addr  = alu_result;
    assign mem_wdata = deex_rs2_data;
    assign mem_we    = deex_mem_we & deex_valid;
    assign mem_re    = deex_mem_re & deex_valid;

    // ---------------------------------------------------------------
    // Writeback mux (combinational)
    // ---------------------------------------------------------------
    reg [15:0] wb_data_r;
    always @(*) begin
        wb_data_r = alu_result;
        case (deex_wb_sel)
            WB_ALU:  wb_data_r = alu_result;
            WB_MEM:  wb_data_r = mem_rdata;
            WB_PC4:  wb_data_r = deex_pc + 16'd4;
            default: wb_data_r = alu_result;
        endcase
    end

    assign wb_data = wb_data_r;
    assign wb_rd   = deex_rd;
    assign wb_we   = deex_reg_we & deex_valid;

endmodule
