-- imm_gen.vhd -- Immediate generator for 16-bit RISC-V microcontroller
-- Extracts and sign-extends immediates from 32-bit instruction word

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity imm_gen is
    port (
        instr    : in  std_logic_vector(31 downto 0);
        imm_type : in  std_logic_vector(2 downto 0);
        imm_out  : out std_logic_vector(15 downto 0)
    );
end entity imm_gen;

architecture rtl of imm_gen is

    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

    signal sign : std_logic;

begin

    sign <= instr(31);

    process (all)
    begin
        imm_out <= x"0000"; -- default to prevent latch
        case imm_type is
            -- I-type: imm[11:0] = {instr[31:20]}
            when IMM_I =>
                imm_out <= (15 downto 11 => sign) & instr(30 downto 20);

            -- S-type: imm[11:0] = {instr[31:25], instr[11:7]}
            when IMM_S =>
                imm_out <= (15 downto 11 => sign) & instr(30 downto 25) & instr(11 downto 7);

            -- B-type: imm[12:1|0] = {sign, instr[7], instr[30:25], instr[11:8], 1'b0}
            when IMM_B =>
                imm_out <= (15 downto 12 => sign) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';

            -- U-type: LUI value = {instr[15:12], 12'b0}
            when IMM_U =>
                imm_out <= instr(15 downto 12) & x"000";

            -- J-type: imm[20:1|0] truncated to 16 bits
            when IMM_J =>
                imm_out <= (15 downto 12 => sign) & instr(20) & instr(30 downto 21) & '0';

            when others =>
                imm_out <= x"0000";
        end case;
    end process;

end architecture rtl;
