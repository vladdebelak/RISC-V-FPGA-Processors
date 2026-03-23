library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv64fp_top is
    port (
        CLK100MHZ : in  std_logic;
        BTNC      : in  std_logic;
        LED       : out std_logic_vector(15 downto 0)
    );
end entity rv64fp_top;

architecture rtl of rv64fp_top is
    signal rst : std_logic;
    signal instr_addr : std_logic_vector(8 downto 0);
    signal instr_data : std_logic_vector(31 downto 0);
    signal mem_addr   : std_logic_vector(63 downto 0);
    signal mem_wdata  : std_logic_vector(63 downto 0);
    signal mem_rdata  : std_logic_vector(63 downto 0);
    signal mem_we     : std_logic;
    signal mem_re     : std_logic;
    signal mem_size   : std_logic_vector(1 downto 0);
    signal mem_unsigned_flag : std_logic;
    signal dm_addr    : std_logic_vector(8 downto 0);
    signal dm_wdata   : std_logic_vector(63 downto 0);
    signal dm_rdata   : std_logic_vector(63 downto 0);
    signal dm_we      : std_logic;
    signal dm_byte_en : std_logic_vector(7 downto 0);
    signal gpio_we    : std_logic;
    signal gpio_wdata : std_logic_vector(15 downto 0);
    signal gpio_rdata : std_logic_vector(15 downto 0);
begin

    u_reset_sync: entity work.reset_sync
        port map (clk => CLK100MHZ, rst_btn => BTNC, rst_sync => rst);

    u_core: entity work.rv64fp_core
        port map (clk => CLK100MHZ, rst => rst,
                  instr_addr => instr_addr, instr_data => instr_data,
                  mem_addr => mem_addr, mem_wdata => mem_wdata, mem_rdata => mem_rdata,
                  mem_we => mem_we, mem_re => mem_re,
                  mem_size => mem_size, mem_unsigned => mem_unsigned_flag);

    u_instr_mem: entity work.instr_mem
        port map (clk => CLK100MHZ, addr => instr_addr, rdata => instr_data);

    u_mem_bus: entity work.mem_bus
        port map (clk => CLK100MHZ, rst => rst,
                  addr => mem_addr, wdata => mem_wdata, we => mem_we, re => mem_re,
                  size => mem_size, is_unsigned => mem_unsigned_flag, rdata => mem_rdata,
                  dm_addr => dm_addr, dm_wdata => dm_wdata, dm_rdata => dm_rdata,
                  dm_we => dm_we, dm_byte_en => dm_byte_en,
                  gpio_we => gpio_we, gpio_wdata => gpio_wdata, gpio_rdata => gpio_rdata);

    u_data_mem: entity work.data_mem
        port map (clk => CLK100MHZ, addr => dm_addr, wdata => dm_wdata,
                  rdata => dm_rdata, we => dm_we, byte_en => dm_byte_en);

    u_gpio_led: entity work.gpio_led
        port map (clk => CLK100MHZ, rst => rst, we => gpio_we,
                  wdata => gpio_wdata, rdata => gpio_rdata, led_out => LED);

end architecture rtl;
