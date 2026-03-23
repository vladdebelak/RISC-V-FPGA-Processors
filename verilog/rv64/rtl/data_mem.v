//============================================================================
// data_mem.v — 512x64-bit Data Memory (Block RAM) with byte-write enables
// Uses Xilinx-recommended byte-write BRAM inference pattern.
//============================================================================

module data_mem (
    input         clk,
    input  [8:0]  addr,
    input  [63:0] wdata,
    output reg [63:0] rdata,
    input         we,
    input  [7:0]  byte_en
);

    (* ram_style = "block" *) reg [63:0] mem [0:511];

    integer i;
    always @(posedge clk) begin
        for (i = 0; i < 8; i = i + 1) begin
            if (we && byte_en[i])
                mem[addr][i*8 +: 8] <= wdata[i*8 +: 8];
        end
        rdata <= mem[addr];
    end

endmodule
