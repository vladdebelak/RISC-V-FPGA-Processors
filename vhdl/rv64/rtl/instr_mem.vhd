-- instr_mem.vhd — 512x32-bit Instruction Memory (Block RAM)
-- Single read port with registered output.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity instr_mem is
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(8 downto 0);
        rdata : out std_logic_vector(31 downto 0)
    );
end entity instr_mem;

architecture rtl of instr_mem is

    type ram_type is array (0 to 511) of std_logic_vector(31 downto 0);

    impure function init_ram(filename : string) return ram_type is
        file hex_file : text open read_mode is filename;
        variable line_buf : line;
        variable data     : std_logic_vector(31 downto 0);
        variable mem      : ram_type := (others => (others => '0'));
    begin
        for i in mem'range loop
            if not endfile(hex_file) then
                readline(hex_file, line_buf);
                hread(line_buf, data);
                mem(i) := data;
            end if;
        end loop;
        return mem;
    end function;

    signal mem : ram_type := init_ram("C:/rv64_vhdl/sw/program.hex");

    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";

begin

    process (clk)
    begin
        if rising_edge(clk) then
            rdata <= mem(to_integer(unsigned(addr)));
        end if;
    end process;

end architecture rtl;
