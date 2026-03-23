library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_round is
    port (
        sign      : in  std_logic;
        guard     : in  std_logic;
        round_bit : in  std_logic;
        sticky    : in  std_logic;
        lsb       : in  std_logic;
        rm        : in  std_logic_vector(2 downto 0);
        round_up  : out std_logic
    );
end entity fp_round;

architecture rtl of fp_round is
    -- Rounding mode encodings (RISC-V fcsr.frm)
    constant RNE : std_logic_vector(2 downto 0) := "000";
    constant RTZ : std_logic_vector(2 downto 0) := "001";
    constant RDN : std_logic_vector(2 downto 0) := "010";
    constant RUP : std_logic_vector(2 downto 0) := "011";
    constant RMM : std_logic_vector(2 downto 0) := "100";
begin

    process(all)
    begin
        round_up <= '0';
        case rm is
            when RNE =>
                round_up <= guard and (round_bit or sticky or lsb);
            when RTZ =>
                round_up <= '0';
            when RDN =>
                round_up <= sign and (guard or round_bit or sticky);
            when RUP =>
                round_up <= (not sign) and (guard or round_bit or sticky);
            when RMM =>
                round_up <= guard;
            when others =>
                round_up <= '0';
        end case;
    end process;

end architecture rtl;
