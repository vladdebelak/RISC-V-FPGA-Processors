// ============================================================================
// fetch.v - Instruction Fetch (IF) Stage
// RV64IFD 5-Stage Pipeline
// Target: Vivado 2020.2
// ============================================================================

module fetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_if,
    input  wire        flush_if,
    input  wire        branch_taken,
    input  wire [63:0] branch_target,
    input  wire        jalr_taken,
    input  wire [63:0] jalr_target,
    output reg  [63:0] pc_out,
    output reg  [63:0] ifid_pc,
    output reg         ifid_valid
);

    // ---- PC Register ----
    reg [63:0] pc_reg;

    always @(posedge clk) begin
        if (rst) begin
            pc_reg <= 64'd0;
        end else if (jalr_taken) begin
            pc_reg <= jalr_target;
        end else if (branch_taken) begin
            pc_reg <= branch_target;
        end else if (!stall_if) begin
            pc_reg <= pc_reg + 64'd4;
        end
    end

    // ---- PC Output (current fetch address) ----
    always @(*) begin
        pc_out = pc_reg;
    end

    // ---- IF/ID Pipeline Register ----
    always @(posedge clk) begin
        if (rst || flush_if) begin
            ifid_pc    <= 64'd0;
            ifid_valid <= 1'b0;
        end else if (!stall_if) begin
            ifid_pc    <= pc_reg;
            ifid_valid <= 1'b1;
        end
        // stall_if: hold current values
    end

endmodule
