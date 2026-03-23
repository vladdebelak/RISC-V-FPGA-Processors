// =============================================================================
// execute.v — EX stage for 3-stage RV64I pipeline
// ALU, branch resolution, JALR, memory interface, writeback mux
// Vivado 2020.2 compatible
// =============================================================================

module execute (
    input        clk,
    input        rst,
    // DE/EX pipeline inputs
    input [63:0] deex_rs1_data,
    input [63:0] deex_rs2_data,
    input [63:0] deex_imm,
    input [63:0] deex_pc,
    input  [4:0] deex_rd,
    input  [4:0] deex_alu_op,
    input        deex_alu_src,
    input        deex_alu_a_sel,
    input        deex_reg_we,
    input        deex_mem_we,
    input        deex_mem_re,
    input  [3:0] deex_branch_op,
    input  [1:0] deex_wb_sel,
    input  [1:0] deex_mem_size,
    input        deex_mem_unsigned,
    input        deex_valid,
    // Memory interface
    output [63:0] mem_addr,
    output [63:0] mem_wdata,
    input  [63:0] mem_rdata,
    output        mem_we,
    output        mem_re,
    output  [1:0] mem_size,
    output        mem_unsigned,
    // Branch feedback to fetch
    output        branch_taken,
    output [63:0] branch_target,
    output        jalr_taken,
    output [63:0] jalr_target,
    // Writeback to decode
    output  [4:0] wb_rd,
    output [63:0] wb_data,
    output        wb_we
);

    // =========================================================================
    // Local parameters
    // =========================================================================

    // ALU ops (5-bit)
    localparam ALU_ADD   = 5'b00000;
    localparam ALU_SUB   = 5'b00001;
    localparam ALU_AND   = 5'b00010;
    localparam ALU_OR    = 5'b00011;
    localparam ALU_XOR   = 5'b00100;
    localparam ALU_SLL   = 5'b00101;
    localparam ALU_SRL   = 5'b00110;
    localparam ALU_SRA   = 5'b00111;
    localparam ALU_SLT   = 5'b01000;
    localparam ALU_SLTU  = 5'b01001;
    localparam ALU_PASS_B = 5'b01010;
    localparam ALU_ADDW  = 5'b10000;
    localparam ALU_SUBW  = 5'b10001;
    localparam ALU_SLLW  = 5'b10101;
    localparam ALU_SRLW  = 5'b10110;
    localparam ALU_SRAW  = 5'b10111;

    // Branch ops (4-bit)
    localparam BR_NONE = 4'd0;
    localparam BR_BEQ  = 4'd1;
    localparam BR_BNE  = 4'd2;
    localparam BR_JAL  = 4'd3;
    localparam BR_JALR = 4'd4;
    localparam BR_BLT  = 4'd5;
    localparam BR_BGE  = 4'd6;
    localparam BR_BLTU = 4'd7;
    localparam BR_BGEU = 4'd8;

    // WB select (2-bit)
    localparam WB_ALU = 2'd0;
    localparam WB_MEM = 2'd1;
    localparam WB_PC4 = 2'd2;

    // =========================================================================
    // ALU input muxes (combinational)
    // =========================================================================
    wire [63:0] alu_a = deex_alu_a_sel ? deex_pc : deex_rs1_data;
    wire [63:0] alu_b = deex_alu_src   ? deex_imm : deex_rs2_data;

    // =========================================================================
    // ALU (combinational)
    // =========================================================================
    reg [63:0] alu_result;
    wire [31:0] alu_a_w = alu_a[31:0];
    wire [31:0] alu_b_w = alu_b[31:0];
    reg  [31:0] result_w;

    always @(*) begin
        alu_result = 64'd0; // default
        result_w   = 32'd0;
        case (deex_alu_op)
            ALU_ADD:   alu_result = alu_a + alu_b;
            ALU_SUB:   alu_result = alu_a - alu_b;
            ALU_AND:   alu_result = alu_a & alu_b;
            ALU_OR:    alu_result = alu_a | alu_b;
            ALU_XOR:   alu_result = alu_a ^ alu_b;
            ALU_SLL:   alu_result = alu_a << alu_b[5:0];
            ALU_SRL:   alu_result = alu_a >> alu_b[5:0];
            ALU_SRA:   alu_result = $signed(alu_a) >>> alu_b[5:0];
            ALU_SLT:   alu_result = {63'd0, $signed(alu_a) < $signed(alu_b)};
            ALU_SLTU:  alu_result = {63'd0, alu_a < alu_b};
            ALU_PASS_B: alu_result = alu_b;
            ALU_ADDW: begin
                result_w   = alu_a_w + alu_b_w;
                alu_result = {{32{result_w[31]}}, result_w};
            end
            ALU_SUBW: begin
                result_w   = alu_a_w - alu_b_w;
                alu_result = {{32{result_w[31]}}, result_w};
            end
            ALU_SLLW: begin
                result_w   = alu_a_w << alu_b[4:0];
                alu_result = {{32{result_w[31]}}, result_w};
            end
            ALU_SRLW: begin
                result_w   = alu_a_w >> alu_b[4:0];
                alu_result = {{32{result_w[31]}}, result_w};
            end
            ALU_SRAW: begin
                result_w   = $signed(alu_a_w) >>> alu_b[4:0];
                alu_result = {{32{result_w[31]}}, result_w};
            end
            default: alu_result = 64'd0;
        endcase
    end

    // =========================================================================
    // Branch comparison flags (combinational)
    // =========================================================================
    wire alu_zero       = (deex_rs1_data == deex_rs2_data);
    wire alu_lt_signed  = ($signed(deex_rs1_data) < $signed(deex_rs2_data));
    wire alu_lt_unsigned = (deex_rs1_data < deex_rs2_data);

    // =========================================================================
    // Branch / JALR resolution (combinational)
    // =========================================================================
    reg  br_taken_r;
    reg  jalr_taken_r;

    assign branch_target = deex_pc + deex_imm;
    assign jalr_target   = (deex_rs1_data + deex_imm) & ~64'd1;

    always @(*) begin
        br_taken_r   = 1'b0; // default
        jalr_taken_r = 1'b0; // default
        if (deex_valid) begin
            case (deex_branch_op)
                BR_JAL:  br_taken_r   = 1'b1;
                BR_JALR: jalr_taken_r = 1'b1;
                BR_BEQ:  br_taken_r   = alu_zero;
                BR_BNE:  br_taken_r   = !alu_zero;
                BR_BLT:  br_taken_r   = alu_lt_signed;
                BR_BGE:  br_taken_r   = !alu_lt_signed;
                BR_BLTU: br_taken_r   = alu_lt_unsigned;
                BR_BGEU: br_taken_r   = !alu_lt_unsigned;
                default: begin
                    br_taken_r   = 1'b0;
                    jalr_taken_r = 1'b0;
                end
            endcase
        end
    end

    assign branch_taken = br_taken_r;
    assign jalr_taken   = jalr_taken_r;

    // =========================================================================
    // Memory interface (combinational outputs)
    // =========================================================================
    assign mem_addr     = alu_result;
    assign mem_wdata    = deex_rs2_data;
    assign mem_we       = deex_mem_we & deex_valid;
    assign mem_re       = deex_mem_re & deex_valid;
    assign mem_size     = deex_mem_size;
    assign mem_unsigned = deex_mem_unsigned;

    // =========================================================================
    // Writeback mux (combinational)
    // =========================================================================
    reg [63:0] wb_data_r;

    always @(*) begin
        wb_data_r = 64'd0; // default
        case (deex_wb_sel)
            WB_ALU: wb_data_r = alu_result;
            WB_MEM: wb_data_r = mem_rdata;
            WB_PC4: wb_data_r = deex_pc + 64'd4;
            default: wb_data_r = 64'd0;
        endcase
    end

    assign wb_data = wb_data_r;
    assign wb_rd   = deex_rd;
    assign wb_we   = deex_reg_we & deex_valid;

endmodule
