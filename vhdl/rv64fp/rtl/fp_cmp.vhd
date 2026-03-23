library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_cmp is
    port (
        a             : in  std_logic_vector(63 downto 0);
        b             : in  std_logic_vector(63 downto 0);
        op            : in  std_logic_vector(2 downto 0);
        result        : out std_logic_vector(63 downto 0);
        flags         : out std_logic_vector(4 downto 0);
        result_is_int : out std_logic
    );
end entity fp_cmp;

architecture rtl of fp_cmp is
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";
    constant NV : natural := 4;

    signal a_sign, b_sign     : std_logic;
    signal a_exp, b_exp       : std_logic_vector(10 downto 0);
    signal a_mant, b_mant     : std_logic_vector(51 downto 0);
    signal a_is_nan, b_is_nan : std_logic;
    signal a_is_snan, b_is_snan : std_logic;
    signal any_nan, any_snan  : std_logic;
    signal a_is_zero, b_is_zero : std_logic;
    signal both_zero          : std_logic;
    signal a_mag, b_mag       : unsigned(62 downto 0);
    signal mag_eq, mag_lt, mag_gt : std_logic;
    signal a_lt_b, a_eq_b     : std_logic;
begin

    a_sign <= a(63); b_sign <= b(63);
    a_exp  <= a(62 downto 52); b_exp <= b(62 downto 52);
    a_mant <= a(51 downto 0);  b_mant <= b(51 downto 0);

    a_is_nan  <= '1' when a_exp = "11111111111" and a_mant /= (51 downto 0 => '0') else '0';
    b_is_nan  <= '1' when b_exp = "11111111111" and b_mant /= (51 downto 0 => '0') else '0';
    a_is_snan <= a_is_nan and (not a_mant(51));
    b_is_snan <= b_is_nan and (not b_mant(51));
    any_nan   <= a_is_nan or b_is_nan;
    any_snan  <= a_is_snan or b_is_snan;

    a_is_zero <= '1' when a_exp = "00000000000" and a_mant = (51 downto 0 => '0') else '0';
    b_is_zero <= '1' when b_exp = "00000000000" and b_mant = (51 downto 0 => '0') else '0';
    both_zero <= a_is_zero and b_is_zero;

    a_mag <= unsigned(a(62 downto 0));
    b_mag <= unsigned(b(62 downto 0));
    mag_eq <= '1' when a_mag = b_mag else '0';
    mag_lt <= '1' when a_mag < b_mag else '0';
    mag_gt <= '1' when a_mag > b_mag else '0';

    -- Signed less-than
    process(all)
    begin
        a_lt_b <= '0';
        if both_zero = '1' then
            a_lt_b <= '0';
        elsif a_sign /= b_sign then
            a_lt_b <= a_sign;
        elsif a_sign = '0' then
            a_lt_b <= mag_lt;
        else
            a_lt_b <= mag_gt;
        end if;
    end process;

    a_eq_b <= '1' when (a = b) or both_zero = '1' else '0';

    -- Main output logic
    process(all)
    begin
        result <= (others => '0');
        flags  <= (others => '0');

        case op is
            -- FEQ.D (op=0)
            when "000" =>
                if any_nan = '1' then
                    result <= (others => '0');
                    if any_snan = '1' then flags(NV) <= '1'; end if;
                else
                    result <= (63 downto 1 => '0') & a_eq_b;
                end if;

            -- FLT.D (op=1)
            when "001" =>
                if any_nan = '1' then
                    result <= (others => '0');
                    flags(NV) <= '1';
                else
                    result <= (63 downto 1 => '0') & a_lt_b;
                end if;

            -- FLE.D (op=2)
            when "010" =>
                if any_nan = '1' then
                    result <= (others => '0');
                    flags(NV) <= '1';
                else
                    result <= (63 downto 1 => '0') & (a_lt_b or a_eq_b);
                end if;

            -- FMIN.D (op=3)
            when "011" =>
                if a_is_nan = '1' and b_is_nan = '1' then
                    result <= CANON_NAN;
                    if any_snan = '1' then flags(NV) <= '1'; end if;
                elsif a_is_nan = '1' then
                    result <= b;
                    if a_is_snan = '1' then flags(NV) <= '1'; end if;
                elsif b_is_nan = '1' then
                    result <= a;
                    if b_is_snan = '1' then flags(NV) <= '1'; end if;
                elsif both_zero = '1' then
                    if a_sign = '1' then result <= a; else result <= b; end if;
                else
                    if a_lt_b = '1' then result <= a; else result <= b; end if;
                end if;

            -- FMAX.D (op=4)
            when "100" =>
                if a_is_nan = '1' and b_is_nan = '1' then
                    result <= CANON_NAN;
                    if any_snan = '1' then flags(NV) <= '1'; end if;
                elsif a_is_nan = '1' then
                    result <= b;
                    if a_is_snan = '1' then flags(NV) <= '1'; end if;
                elsif b_is_nan = '1' then
                    result <= a;
                    if b_is_snan = '1' then flags(NV) <= '1'; end if;
                elsif both_zero = '1' then
                    if a_sign = '0' then result <= a; else result <= b; end if;
                else
                    if a_lt_b = '0' and a_eq_b = '0' then result <= a; else result <= b; end if;
                end if;

            when others =>
                result <= (others => '0');
                flags  <= (others => '0');
        end case;
    end process;

    result_is_int <= '1' when unsigned(op) <= 2 else '0';

end architecture rtl;
