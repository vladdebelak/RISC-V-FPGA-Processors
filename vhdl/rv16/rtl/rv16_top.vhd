-- rv16_top.vhd
-- Top-level wrapper for the 16-bit RISC-V microcontroller on Basys 3.
-- CPU runs at full 100 MHz -- no clock divider.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv16_top is
    port (
        CLK100MHZ : in  std_logic;
        BTNC      : in  std_logic;         -- center button -- active-high reset
        LED       : out std_logic_vector(15 downto 0)
    );
end entity rv16_top;

architecture rtl of rv16_top is

    -- Synchronized reset (active high, two-FF synchronizer)
    signal rst : std_logic;

    -- Instruction memory interface
    signal instr_addr : std_logic_vector(7 downto 0);
    signal instr_data : std_logic_vector(31 downto 0);

    -- Data memory / bus interface
    signal mem_addr  : std_logic_vector(15 downto 0);
    signal mem_wdata : std_logic_vector(15 downto 0);
    signal mem_rdata : std_logic_vector(15 downto 0);
    signal mem_we    : std_logic;
    signal mem_re    : std_logic;

    -- Data bus internal signals
    signal dm_addr   : std_logic_vector(7 downto 0);
    signal dm_wdata  : std_logic_vector(15 downto 0);
    signal dm_rdata  : std_logic_vector(15 downto 0);
    signal dm_we     : std_logic;
    signal dm_re     : std_logic;

    signal gpio_rdata : std_logic_vector(15 downto 0);
    signal gpio_we    : std_logic;
    signal gpio_wdata : std_logic_vector(15 downto 0);

begin

    -- Reset synchronizer
    u_reset_sync : entity work.reset_sync
        port map (
            clk      => CLK100MHZ,
            rst_btn  => BTNC,
            rst_sync => rst
        );

    -- CPU core
    u_core : entity work.rv16_core
        port map (
            clk        => CLK100MHZ,
            rst        => rst,
            instr_addr => instr_addr,
            instr_data => instr_data,
            mem_addr   => mem_addr,
            mem_wdata  => mem_wdata,
            mem_rdata  => mem_rdata,
            mem_we     => mem_we,
            mem_re     => mem_re
        );

    -- Instruction memory (256 x 32-bit single-port ROM/BRAM)
    u_instr_mem : entity work.instr_mem
        port map (
            clk   => CLK100MHZ,
            addr  => instr_addr,
            rdata => instr_data
        );

    -- Data bus (memory-mapped: data RAM + GPIO LEDs)
    u_mem_bus : entity work.mem_bus
        port map (
            clk        => CLK100MHZ,
            rst        => rst,
            addr       => mem_addr,
            wdata      => mem_wdata,
            rdata      => mem_rdata,
            we         => mem_we,
            re         => mem_re,
            dm_addr    => dm_addr,
            dm_wdata   => dm_wdata,
            dm_rdata   => dm_rdata,
            dm_we      => dm_we,
            dm_re      => dm_re,
            gpio_wdata => gpio_wdata,
            gpio_rdata => gpio_rdata,
            gpio_we    => gpio_we
        );

    -- Data memory (RAM)
    u_data_mem : entity work.data_mem
        port map (
            clk   => CLK100MHZ,
            addr  => dm_addr,
            wdata => dm_wdata,
            rdata => dm_rdata,
            we    => dm_we,
            re    => dm_re
        );

    -- GPIO -- 16-bit LED register
    u_gpio_led : entity work.gpio_led
        port map (
            clk     => CLK100MHZ,
            rst     => rst,
            wdata   => gpio_wdata,
            rdata   => gpio_rdata,
            we      => gpio_we,
            led_out => LED
        );

end architecture rtl;
