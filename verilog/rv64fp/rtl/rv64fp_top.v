`timescale 1ns / 1ps

module rv64fp_top (
    input  wire        CLK100MHZ,
    input  wire        BTNC,
    output wire [15:0] LED
);

    // =========================================================================
    // Reset synchronizer
    // =========================================================================
    wire rst;

    reset_sync u_reset_sync (
        .clk      (CLK100MHZ),
        .rst_btn  (BTNC),
        .rst_sync (rst)
    );

    // =========================================================================
    // Core <-> memory wires
    // =========================================================================
    wire [8:0]  instr_addr;
    wire [31:0] instr_data;

    wire [63:0] mem_addr;
    wire [63:0] mem_wdata;
    wire [63:0] mem_rdata;
    wire        mem_we;
    wire        mem_re;
    wire [1:0]  mem_size;
    wire        mem_unsigned_flag;

    // =========================================================================
    // Memory bus <-> peripherals
    // =========================================================================
    wire [8:0]  dm_addr;
    wire [63:0] dm_wdata;
    wire [63:0] dm_rdata;
    wire        dm_we;
    wire [7:0]  dm_byte_en;
    wire        gpio_we;
    wire [15:0] gpio_wdata;
    wire [15:0] gpio_rdata;

    // =========================================================================
    // Core
    // =========================================================================
    rv64fp_core u_core (
        .clk          (CLK100MHZ),
        .rst          (rst),
        .instr_addr   (instr_addr),
        .instr_data   (instr_data),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_rdata    (mem_rdata),
        .mem_we       (mem_we),
        .mem_re       (mem_re),
        .mem_size     (mem_size),
        .mem_unsigned (mem_unsigned_flag)
    );

    // =========================================================================
    // Instruction memory
    // =========================================================================
    instr_mem u_instr_mem (
        .clk   (CLK100MHZ),
        .addr  (instr_addr),
        .rdata (instr_data)
    );

    // =========================================================================
    // Memory bus (address decoder)
    // =========================================================================
    mem_bus u_mem_bus (
        .clk          (CLK100MHZ),
        .rst          (rst),
        // CPU side
        .addr         (mem_addr),
        .wdata        (mem_wdata),
        .we           (mem_we),
        .re           (mem_re),
        .size         (mem_size),
        .is_unsigned  (mem_unsigned_flag),
        .rdata        (mem_rdata),
        // Data memory port
        .dm_addr      (dm_addr),
        .dm_wdata     (dm_wdata),
        .dm_rdata     (dm_rdata),
        .dm_we        (dm_we),
        .dm_byte_en   (dm_byte_en),
        // GPIO port
        .gpio_we      (gpio_we),
        .gpio_wdata   (gpio_wdata),
        .gpio_rdata   (gpio_rdata)
    );

    // =========================================================================
    // Data memory
    // =========================================================================
    data_mem u_data_mem (
        .clk     (CLK100MHZ),
        .addr    (dm_addr),
        .wdata   (dm_wdata),
        .rdata   (dm_rdata),
        .we      (dm_we),
        .byte_en (dm_byte_en)
    );

    // =========================================================================
    // GPIO LEDs
    // =========================================================================
    gpio_led u_gpio_led (
        .clk    (CLK100MHZ),
        .rst    (rst),
        .we     (gpio_we),
        .wdata  (gpio_wdata),
        .rdata  (gpio_rdata),
        .led_out(LED)
    );

endmodule
