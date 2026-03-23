-- regfile.vhd -- 16x16-bit register file with x0 hardwired to zero
-- Dual combinational read, single synchronous write

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
    port (
        clk      : in  std_logic;
        rs1_addr : in  std_logic_vector(3 downto 0);
        rs2_addr : in  std_logic_vector(3 downto 0);
        rs1_data : out std_logic_vector(15 downto 0);
        rs2_data : out std_logic_vector(15 downto 0);
        wd_addr  : in  std_logic_vector(3 downto 0);
        wd_data  : in  std_logic_vector(15 downto 0);
        wd_en    : in  std_logic
    );
end entity regfile;

architecture rtl of regfile is

    type reg_array_t is array (0 to 15) of std_logic_vector(15 downto 0);
    signal regs : reg_array_t := (others => x"0000");

begin

    -- Synchronous write -- x0 is never written
    process (clk)
    begin
        if rising_edge(clk) then
            if wd_en = '1' and wd_addr /= "0000" then
                regs(to_integer(unsigned(wd_addr))) <= wd_data;
            end if;
        end if;
    end process;

    -- Combinational read -- x0 always returns 0
    rs1_data <= x"0000" when rs1_addr = "0000"
                else regs(to_integer(unsigned(rs1_addr)));
    rs2_data <= x"0000" when rs2_addr = "0000"
                else regs(to_integer(unsigned(rs2_addr)));

end architecture rtl;
