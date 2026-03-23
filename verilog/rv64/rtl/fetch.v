// =============================================================================
// fetch.v — IF stage for 3-stage RV64I pipeline
// 64-bit PC with IF/DE pipeline register
// Vivado 2020.2 compatible
// =============================================================================

module fetch (
    input        clk,
    input        rst,
    input        stall,
    input        flush,
    input        branch_taken,
    input [63:0] branch_target,
    input        jalr_taken,
    input [63:0] jalr_target,

    output reg [63:0] pc_out,
    output reg [63:0] ifde_pc,
    output reg        ifde_valid
);

    // -------------------------------------------------------------------------
    // PC update — sequential
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pc_out <= 64'd0;
        end else if (jalr_taken) begin
            pc_out <= jalr_target;
        end else if (branch_taken) begin
            pc_out <= branch_target;
        end else if (!stall) begin
            pc_out <= pc_out + 64'd4;
        end
    end

    // -------------------------------------------------------------------------
    // IF/DE pipeline register — sequential
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            ifde_pc    <= 64'd0;
            ifde_valid <= 1'b0;
        end else if (!stall) begin
            ifde_pc    <= pc_out;
            ifde_valid <= 1'b1;
        end
    end

endmodule
