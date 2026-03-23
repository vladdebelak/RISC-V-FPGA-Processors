// rv16_top.v
// Top-level wrapper for the 16-bit RISC-V microcontroller on Basys 3.
// CPU runs at full 100 MHz — no clock divider.

module rv16_top (
    input         CLK100MHZ,
    input         BTNC,        // center button — active-high reset
    output [15:0] LED
);

    // ----------------------------------------------------------------
    // Synchronized reset  (active high, two-FF synchronizer)
    // ----------------------------------------------------------------
    wire rst;

    reset_sync u_reset_sync (
        .clk      (CLK100MHZ),
        .rst_btn  (BTNC),
        .rst_sync (rst)
    );

    // ----------------------------------------------------------------
    // Instruction memory interface
    // ----------------------------------------------------------------
    wire [7:0]  instr_addr;
    wire [31:0] instr_data;

    // ----------------------------------------------------------------
    // Data memory / bus interface
    // ----------------------------------------------------------------
    wire [15:0] mem_addr;
    wire [15:0] mem_wdata;
    wire [15:0] mem_rdata;
    wire        mem_we;
    wire        mem_re;

    // ----------------------------------------------------------------
    // CPU core
    // ----------------------------------------------------------------
    rv16_core u_core (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .instr_addr (instr_addr),
        .instr_data (instr_data),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_rdata  (mem_rdata),
        .mem_we     (mem_we),
        .mem_re     (mem_re)
    );

    // ----------------------------------------------------------------
    // Instruction memory  (256 x 32-bit single-port ROM/BRAM)
    // ----------------------------------------------------------------
    instr_mem u_instr_mem (
        .clk   (CLK100MHZ),
        .addr  (instr_addr),
        .rdata (instr_data)
    );

    // ----------------------------------------------------------------
    // Data bus  (memory-mapped: data RAM + GPIO LEDs)
    // ----------------------------------------------------------------
    wire [7:0]  dm_addr;
    wire [15:0] dm_wdata;
    wire [15:0] dm_rdata;
    wire        dm_we;
    wire        dm_re;

    wire [15:0] gpio_rdata;
    wire        gpio_we;
    wire [15:0] gpio_wdata;

    mem_bus u_mem_bus (
        .clk        (CLK100MHZ),
        .rst        (rst),
        // Core side
        .addr       (mem_addr),
        .wdata      (mem_wdata),
        .rdata      (mem_rdata),
        .we         (mem_we),
        .re         (mem_re),
        // Data memory port
        .dm_addr    (dm_addr),
        .dm_wdata   (dm_wdata),
        .dm_rdata   (dm_rdata),
        .dm_we      (dm_we),
        .dm_re      (dm_re),
        // GPIO port
        .gpio_wdata (gpio_wdata),
        .gpio_rdata (gpio_rdata),
        .gpio_we    (gpio_we)
    );

    // ----------------------------------------------------------------
    // Data memory  (RAM)
    // ----------------------------------------------------------------
    data_mem u_data_mem (
        .clk   (CLK100MHZ),
        .addr  (dm_addr),
        .wdata (dm_wdata),
        .rdata (dm_rdata),
        .we    (dm_we),
        .re    (dm_re)
    );

    // ----------------------------------------------------------------
    // GPIO — 16-bit LED register
    // ----------------------------------------------------------------
    gpio_led u_gpio_led (
        .clk     (CLK100MHZ),
        .rst     (rst),
        .wdata   (gpio_wdata),
        .rdata   (gpio_rdata),
        .we      (gpio_we),
        .led_out (LED)
    );

endmodule
