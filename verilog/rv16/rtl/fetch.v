// fetch.v — Stage 1: PC management and IF/DE pipeline register
// 16-bit 3-stage RISC-V microcontroller
// PC increments by 4 (word-aligned 32-bit instructions)

module fetch (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,
    input  wire        branch_taken,
    input  wire [15:0] branch_target,
    output reg  [15:0] pc_out,
    output reg  [15:0] ifde_pc,
    output reg         ifde_valid
);

    // ---------------------------------------------------------------
    // PC register
    // ---------------------------------------------------------------
    reg [15:0] pc_reg;

    always @(posedge clk) begin
        if (rst)
            pc_reg <= 16'h0000;
        else if (stall)
            pc_reg <= pc_reg;           // hold
        else if (branch_taken)
            pc_reg <= branch_target;
        else
            pc_reg <= pc_reg + 16'd4;
    end

    // pc_out drives instruction memory address (top-level divides by 4)
    always @(*) begin
        pc_out = pc_reg;
    end

    // ---------------------------------------------------------------
    // IF/DE pipeline register
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            ifde_pc    <= 16'h0000;
            ifde_valid <= 1'b0;
        end else if (stall) begin
            ifde_pc    <= ifde_pc;
            ifde_valid <= ifde_valid;
        end else begin
            ifde_pc    <= pc_reg;
            ifde_valid <= 1'b1;
        end
    end

endmodule
