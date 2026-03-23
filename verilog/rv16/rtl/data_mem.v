// data_mem.v — 256x16-bit data memory (BRAM)
// Single synchronous read/write port

module data_mem (
    input  wire        clk,
    input  wire [7:0]  addr,
    input  wire [15:0] wdata,
    output reg  [15:0] rdata,
    input  wire        we,
    input  wire        re
);

    (* ram_style = "block" *)
    reg [15:0] mem [0:255];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
        if (re)
            rdata <= mem[addr];
    end

endmodule
