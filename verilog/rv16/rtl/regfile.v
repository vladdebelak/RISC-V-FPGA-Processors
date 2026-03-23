// regfile.v — 16x16-bit register file with x0 hardwired to zero
// Dual combinational read, single synchronous write

module regfile (
    input  wire        clk,
    input  wire [3:0]  rs1_addr,
    input  wire [3:0]  rs2_addr,
    output wire [15:0] rs1_data,
    output wire [15:0] rs2_data,
    input  wire [3:0]  wd_addr,
    input  wire [15:0] wd_data,
    input  wire        wd_en
);

    reg [15:0] regs [0:15];

    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            regs[i] = 16'h0000;
    end

    // Synchronous write — x0 is never written
    always @(posedge clk) begin
        if (wd_en && (wd_addr != 4'b0000))
            regs[wd_addr] <= wd_data;
    end

    // Combinational read — x0 always returns 0
    assign rs1_data = (rs1_addr == 4'b0000) ? 16'h0000 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 4'b0000) ? 16'h0000 : regs[rs2_addr];

endmodule
