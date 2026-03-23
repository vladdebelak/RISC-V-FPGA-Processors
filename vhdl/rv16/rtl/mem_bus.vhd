-- mem_bus.vhd -- Address decoder / memory bus
-- Routes CPU data bus to data_mem or gpio_led based on address

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mem_bus is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;

        -- From CPU
        addr       : in  std_logic_vector(15 downto 0);
        wdata      : in  std_logic_vector(15 downto 0);
        we         : in  std_logic;
        re         : in  std_logic;

        -- To data memory
        dm_addr    : out std_logic_vector(7 downto 0);
        dm_wdata   : out std_logic_vector(15 downto 0);
        dm_rdata   : in  std_logic_vector(15 downto 0);
        dm_we      : out std_logic;
        dm_re      : out std_logic;

        -- To GPIO
        gpio_we    : out std_logic;
        gpio_wdata : out std_logic_vector(15 downto 0);
        gpio_rdata : in  std_logic_vector(15 downto 0);

        -- Back to CPU
        rdata      : out std_logic_vector(15 downto 0)
    );
end entity mem_bus;

architecture rtl of mem_bus is

    -- Address decode signals
    signal sel_gpio : std_logic;
    signal sel_dmem : std_logic;

    -- Latched select for read-data mux (data returns one cycle after re)
    signal sel_gpio_r : std_logic;
    signal sel_dmem_r : std_logic;

begin

    sel_gpio <= '1' when addr(15 downto 12) = x"F" else '0';
    sel_dmem <= '1' when addr(15 downto 12) = x"1" else '0';

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sel_gpio_r <= '0';
                sel_dmem_r <= '0';
            elsif re = '1' then
                sel_gpio_r <= sel_gpio;
                sel_dmem_r <= sel_dmem;
            end if;
        end if;
    end process;

    -- Data memory connections
    dm_addr  <= addr(8 downto 1); -- byte to word index
    dm_wdata <= wdata;
    dm_we    <= we and sel_dmem;
    dm_re    <= re and sel_dmem;

    -- GPIO connections
    gpio_wdata <= wdata;
    gpio_we    <= we and sel_gpio;

    -- Read data mux -- uses latched select
    process (all)
    begin
        rdata <= x"0000"; -- default to prevent latch
        if sel_gpio_r = '1' then
            rdata <= gpio_rdata;
        elsif sel_dmem_r = '1' then
            rdata <= dm_rdata;
        end if;
    end process;

end architecture rtl;
