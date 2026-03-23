`timescale 1ns/1ps
module tb_rv16_core;

    reg         clk;
    reg         rst_n;

    // Core memory interface
    wire [15:0] imem_addr;
    wire [15:0] instr;
    wire        mem_we;
    wire [15:0] mem_addr;
    wire [15:0] mem_wdata;
    wire [15:0] mem_rdata;

    // ----------------------------------------------------------
    // Instruction memory (256 x 16)
    // ----------------------------------------------------------
    reg [15:0] imem [0:255];
    initial begin
        $readmemh("program_test.hex", imem);
    end
    assign instr = imem[imem_addr[8:1]]; // word-addressed

    // ----------------------------------------------------------
    // Data memory (256 x 16)
    // ----------------------------------------------------------
    reg [15:0] dmem [0:255];
    reg [15:0] mem_rdata_reg;

    always @(posedge clk) begin
        if (mem_we && mem_addr[15:8] != 8'hFF) begin
            dmem[mem_addr[8:1]] <= mem_wdata;
        end
        mem_rdata_reg <= dmem[mem_addr[8:1]];
    end
    assign mem_rdata = mem_rdata_reg;

    // ----------------------------------------------------------
    // DUT
    // ----------------------------------------------------------
    rv16_core uut (
        .clk(clk),
        .rst_n(rst_n),
        .instr(instr),
        .imem_addr(imem_addr),
        .mem_rdata(mem_rdata),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata)
    );

    // ----------------------------------------------------------
    // Clock: 100 MHz
    // ----------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // Waveform dump
    initial begin
        $dumpfile("rv16_core.vcd");
        $dumpvars(0, tb_rv16_core);
    end

    // ----------------------------------------------------------
    // Monitor each cycle
    // ----------------------------------------------------------
    integer cycle = 0;
    reg     gpio_seen = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            $display("cycle %0d : PC=%h instr=%h mem_we=%b mem_addr=%h mem_wdata=%h",
                     cycle, imem_addr, instr, mem_we, mem_addr, mem_wdata);

            if (mem_we && mem_addr == 16'hFF00) begin
                $display("  >>> GPIO WRITE: %h <<<", mem_wdata);
                gpio_seen <= 1;
            end
        end
        cycle <= cycle + 1;
    end

    // ----------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------
    initial begin
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("Reset released at cycle %0d", cycle);

        repeat (500) @(posedge clk);

        $display("");
        $display("==========================================");
        if (gpio_seen)
            $display("PASS: GPIO write to 0xFF00 detected");
        else
            $display("FAIL: No GPIO write to 0xFF00 detected in 500 cycles");
        $display("==========================================");
        $finish;
    end

endmodule
