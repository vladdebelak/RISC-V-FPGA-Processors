// instr_mem.v — 256x32-bit instruction memory (BRAM)
// Single synchronous read port, initialized from program.hex

module instr_mem (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [31:0] rdata
);

    (* ram_style = "block" *)
    reg [31:0] mem [0:255];

    initial begin
        $readmemh("C:/rv16_build/sw/program.hex", mem);
    end

    always @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
