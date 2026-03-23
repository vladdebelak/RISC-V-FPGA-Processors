library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity instr_mem is
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(8 downto 0);
        rdata : out std_logic_vector(31 downto 0)
    );
end entity instr_mem;

architecture rtl of instr_mem is
    type mem_array_t is array (0 to 511) of std_logic_vector(31 downto 0);

    impure function init_mem return mem_array_t is
        file hex_file : text open read_mode is "C:/rv64fp_vhdl/sw/program.hex";
        variable line_v : line;
        variable word_v : std_logic_vector(31 downto 0);
        variable mem_v  : mem_array_t := (others => (others => '0'));
        variable idx    : integer := 0;
    begin
        while not endfile(hex_file) and idx < 512 loop
            readline(hex_file, line_v);
            hread(line_v, word_v);
            mem_v(idx) := word_v;
            idx := idx + 1;
        end loop;
        return mem_v;
    end function;

    attribute ram_style : string;
    signal mem : mem_array_t := init_mem;
    attribute ram_style of mem : signal is "block";

    signal rdata_r : std_logic_vector(31 downto 0);
begin

    process(clk)
    begin
        if rising_edge(clk) then
            rdata_r <= mem(to_integer(unsigned(addr)));
        end if;
    end process;

    rdata <= rdata_r;

end architecture rtl;
