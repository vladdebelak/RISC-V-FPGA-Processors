-- alu.vhd -- 16-bit ALU for RISC-V microcontroller
-- Operations: ADD, SUB, AND, OR, XOR, PASS_B

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port (
        a      : in  std_logic_vector(15 downto 0);
        b      : in  std_logic_vector(15 downto 0);
        alu_op : in  std_logic_vector(3 downto 0);
        result : out std_logic_vector(15 downto 0);
        zero   : out std_logic
    );
end entity alu;

architecture rtl of alu is

    constant ALU_ADD    : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB    : std_logic_vector(3 downto 0) := "0001";
    constant ALU_AND    : std_logic_vector(3 downto 0) := "0010";
    constant ALU_OR     : std_logic_vector(3 downto 0) := "0011";
    constant ALU_XOR    : std_logic_vector(3 downto 0) := "0100";
    constant ALU_PASS_B : std_logic_vector(3 downto 0) := "0101";

    signal result_i : std_logic_vector(15 downto 0);

begin

    zero   <= '1' when result_i = x"0000" else '0';
    result <= result_i;

    process (all)
    begin
        result_i <= x"0000"; -- default to prevent latch
        case alu_op is
            when ALU_ADD    => result_i <= std_logic_vector(unsigned(a) + unsigned(b));
            when ALU_SUB    => result_i <= std_logic_vector(unsigned(a) - unsigned(b));
            when ALU_AND    => result_i <= a and b;
            when ALU_OR     => result_i <= a or b;
            when ALU_XOR    => result_i <= a xor b;
            when ALU_PASS_B => result_i <= b;
            when others     => result_i <= x"0000";
        end case;
    end process;

end architecture rtl;
