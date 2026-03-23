-- data_mem.vhd — 512x64-bit Data Memory (Block RAM) with byte-write enables
-- Uses Xilinx-recommended byte-write BRAM inference pattern.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_mem is
    port (
        clk     : in  std_logic;
        addr    : in  std_logic_vector(8 downto 0);
        wdata   : in  std_logic_vector(63 downto 0);
        rdata   : out std_logic_vector(63 downto 0);
        we      : in  std_logic;
        byte_en : in  std_logic_vector(7 downto 0)
    );
end entity data_mem;

architecture rtl of data_mem is

    type ram_type is array (0 to 511) of std_logic_vector(63 downto 0);
    signal mem : ram_type := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";

begin

    process (clk)
        variable idx : integer;
    begin
        if rising_edge(clk) then
            idx := to_integer(unsigned(addr));
            for i in 0 to 7 loop
                if we = '1' and byte_en(i) = '1' then
                    mem(idx)(i*8+7 downto i*8) <= wdata(i*8+7 downto i*8);
                end if;
            end loop;
            rdata <= mem(idx);
        end if;
    end process;

end architecture rtl;
