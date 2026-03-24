`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// SVA properties for mem_bus module (RV64FP)
// Verifies address decoding, write-enable mutual exclusion, and byte-enable
// generation for the memory bus.
//////////////////////////////////////////////////////////////////////////////

module sva_mem_bus_props (
    input logic        clk,
    input logic        rst,

    // From CPU
    input logic [63:0] addr,
    input logic [63:0] wdata,
    input logic        we,
    input logic        re,
    input logic [1:0]  size,
    input logic        is_unsigned,

    // To/from data memory
    input logic [8:0]  dm_addr,
    input logic [63:0] dm_wdata,
    input logic [63:0] dm_rdata,
    input logic        dm_we,
    input logic [7:0]  dm_byte_en,

    // To/from GPIO
    input logic        gpio_we,
    input logic [15:0] gpio_wdata,
    input logic [15:0] gpio_rdata,

    // To CPU
    input logic [63:0] rdata
);

    default clocking cb @(posedge clk); endclocking

    // -----------------------------------------------------------------------
    // Internal: replicate address decode logic for assertions
    // -----------------------------------------------------------------------
    wire sel_gpio = (addr[15:8] == 8'hFF);
    wire sel_dmem = (addr[15:12] == 4'h1);

    // -----------------------------------------------------------------------
    // P_WE_MUTUAL_EXCLUSION: Cannot write both DMEM and GPIO simultaneously
    // -----------------------------------------------------------------------
    P_WE_MUTUAL_EXCLUSION: assert property (
        @(posedge clk) !(dm_we && gpio_we)
    ) else $error("P_WE_MUTUAL_EXCLUSION: both dm_we and gpio_we asserted");

    // -----------------------------------------------------------------------
    // P_GPIO_DECODE: GPIO address with write enables gpio_we
    // -----------------------------------------------------------------------
    P_GPIO_DECODE: assert property (
        @(posedge clk) addr[15:8] == 8'hFF && we |-> gpio_we
    ) else $error("P_GPIO_DECODE: gpio_we not asserted for GPIO address write");

    // -----------------------------------------------------------------------
    // P_DMEM_DECODE: DMEM address with write enables dm_we
    // -----------------------------------------------------------------------
    P_DMEM_DECODE: assert property (
        @(posedge clk) addr[15:12] == 4'h1 && we |-> dm_we
    ) else $error("P_DMEM_DECODE: dm_we not asserted for DMEM address write");

    // -----------------------------------------------------------------------
    // P_NO_WRITE_NO_ENABLE: No write means no write-enables asserted
    // -----------------------------------------------------------------------
    P_NO_WRITE_NO_ENABLE: assert property (
        @(posedge clk) !we |-> !dm_we && !gpio_we
    ) else $error("P_NO_WRITE_NO_ENABLE: write-enable asserted without we");

    // -----------------------------------------------------------------------
    // P_GPIO_NOT_DMEM: GPIO write does not assert dm_we
    // -----------------------------------------------------------------------
    P_GPIO_NOT_DMEM: assert property (
        @(posedge clk) addr[15:8] == 8'hFF && we |-> !dm_we
    ) else $error("P_GPIO_NOT_DMEM: dm_we asserted during GPIO write");

    // -----------------------------------------------------------------------
    // P_DMEM_NOT_GPIO: DMEM write (non-GPIO range) does not assert gpio_we
    // -----------------------------------------------------------------------
    P_DMEM_NOT_GPIO: assert property (
        @(posedge clk)
        addr[15:12] == 4'h1 && addr[15:8] != 8'hFF && we |-> !gpio_we
    ) else $error("P_DMEM_NOT_GPIO: gpio_we asserted during DMEM write");

    // -----------------------------------------------------------------------
    // P_BYTE_EN_BYTE: Byte access enables exactly 1 byte lane
    // -----------------------------------------------------------------------
    P_BYTE_EN_BYTE: assert property (
        @(posedge clk) size == 2'b00 |-> $countones(dm_byte_en) == 1
    ) else $error("P_BYTE_EN_BYTE: byte access did not enable exactly 1 lane");

    // -----------------------------------------------------------------------
    // P_BYTE_EN_DOUBLE: Doubleword access enables all 8 byte lanes
    // -----------------------------------------------------------------------
    P_BYTE_EN_DOUBLE: assert property (
        @(posedge clk) size == 2'b11 |-> dm_byte_en == 8'hFF
    ) else $error("P_BYTE_EN_DOUBLE: doubleword access did not enable all lanes");

    // -----------------------------------------------------------------------
    // C_GPIO_WRITE: Cover a GPIO write
    // -----------------------------------------------------------------------
    C_GPIO_WRITE: cover property (
        @(posedge clk) gpio_we
    );

    // -----------------------------------------------------------------------
    // C_DMEM_WRITE: Cover a DMEM write
    // -----------------------------------------------------------------------
    C_DMEM_WRITE: cover property (
        @(posedge clk) dm_we
    );

endmodule
