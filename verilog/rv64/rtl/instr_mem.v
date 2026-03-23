//============================================================================
// instr_mem.v — 512x32-bit Instruction Memory (Block RAM)
// Single read port with registered output.
//============================================================================

module instr_mem (
    input         clk,
    input  [8:0]  addr,
    output reg [31:0] rdata
);

    (* ram_style = "block" *) reg [31:0] mem [0:511];

    initial begin
        $readmemh("C:/rv64_build/sw/program.hex", mem);
    end

    always @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
