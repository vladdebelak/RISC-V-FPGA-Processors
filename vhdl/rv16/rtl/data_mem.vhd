-- data_mem.vhd -- 256x16-bit data memory (BRAM)
-- Single synchronous read/write port

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_mem is
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(7 downto 0);
        wdata : in  std_logic_vector(15 downto 0);
        rdata : out std_logic_vector(15 downto 0);
        we    : in  std_logic;
        re    : in  std_logic
    );
end entity data_mem;

architecture rtl of data_mem is

    type ram_type is array (0 to 255) of std_logic_vector(15 downto 0);
    signal mem : ram_type := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(unsigned(addr))) <= wdata;
            end if;
            if re = '1' then
                rdata <= mem(to_integer(unsigned(addr)));
            end if;
        end if;
    end process;

end architecture rtl;
