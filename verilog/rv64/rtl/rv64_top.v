// rv64_top.v — Top-level for RV64I MCU on Basys 3
`default_nettype none

module rv64_top (
    input  wire        CLK100MHZ,
    input  wire        BTNC,
    output wire [15:0] LED
);

    // ---------------------------------------------------------------
    // Reset synchroniser (active-high)
    // ---------------------------------------------------------------
    wire rst_sync;

    reset_sync u_reset_sync (
        .clk      (CLK100MHZ),
        .rst_btn  (BTNC),
        .rst_sync (rst_sync)
    );

    // ---------------------------------------------------------------
    // Core ↔ memory wires
    // ---------------------------------------------------------------
    wire [8:0]  instr_addr;
    wire [31:0] instr_data;

    wire [63:0] mem_addr;
    wire [63:0] mem_wdata;
    wire [63:0] mem_rdata;
    wire        mem_we;
    wire        mem_re;
    wire [1:0]  mem_size;
    wire        mem_unsigned;

    // ---------------------------------------------------------------
    // RV64I core
    // ---------------------------------------------------------------
    rv64_core u_core (
        .clk          (CLK100MHZ),
        .rst          (rst_sync),
        .instr_addr   (instr_addr),
        .instr_data   (instr_data),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_rdata    (mem_rdata),
        .mem_we       (mem_we),
        .mem_re       (mem_re),
        .mem_size     (mem_size),
        .mem_unsigned (mem_unsigned)
    );

    // ---------------------------------------------------------------
    // Instruction memory (512 x 32-bit)
    // ---------------------------------------------------------------
    instr_mem u_instr_mem (
        .clk   (CLK100MHZ),
        .addr  (instr_addr),
        .rdata (instr_data)
    );

    // ---------------------------------------------------------------
    // Memory bus → data_mem + gpio_led
    // ---------------------------------------------------------------
    wire [8:0]  dm_addr;
    wire [63:0] dm_wdata;
    wire        dm_we;
    wire [7:0]  dm_byte_en;
    wire [63:0] dm_rdata;

    wire        gpio_we;
    wire [15:0] gpio_wdata;
    wire [15:0] gpio_rdata;

    mem_bus u_mem_bus (
        .clk          (CLK100MHZ),
        .rst          (rst_sync),
        // CPU side
        .addr         (mem_addr),
        .wdata        (mem_wdata),
        .we           (mem_we),
        .re           (mem_re),
        .size         (mem_size),
        .is_unsigned  (mem_unsigned),
        .rdata        (mem_rdata),
        // Data memory side
        .dm_addr      (dm_addr),
        .dm_wdata     (dm_wdata),
        .dm_we        (dm_we),
        .dm_byte_en   (dm_byte_en),
        .dm_rdata     (dm_rdata),
        // GPIO side
        .gpio_we      (gpio_we),
        .gpio_wdata   (gpio_wdata),
        .gpio_rdata   (gpio_rdata)
    );

    // ---------------------------------------------------------------
    // Data memory (512 x 64-bit, byte-addressable)
    // ---------------------------------------------------------------
    data_mem u_data_mem (
        .clk      (CLK100MHZ),
        .addr     (dm_addr),
        .wdata    (dm_wdata),
        .we       (dm_we),
        .byte_en  (dm_byte_en),
        .rdata    (dm_rdata)
    );

    // ---------------------------------------------------------------
    // GPIO — 16-bit LED register
    // ---------------------------------------------------------------
    gpio_led u_gpio_led (
        .clk      (CLK100MHZ),
        .rst      (rst_sync),
        .we       (gpio_we),
        .wdata    (gpio_wdata),
        .rdata    (gpio_rdata),
        .led_out  (LED)
    );

endmodule
