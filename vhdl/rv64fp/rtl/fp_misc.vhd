library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_misc is
    port (
        a             : in  std_logic_vector(63 downto 0);
        b             : in  std_logic_vector(63 downto 0);
        op            : in  std_logic_vector(2 downto 0);
        result        : out std_logic_vector(63 downto 0);
        result_is_int : out std_logic
    );
end entity fp_misc;

architecture rtl of fp_misc is
    signal a_sign     : std_logic;
    signal a_exp      : std_logic_vector(10 downto 0);
    signal a_mant     : std_logic_vector(51 downto 0);
    signal a_exp_zero : std_logic;
    signal a_exp_max  : std_logic;
    signal a_mant_zero: std_logic;
    signal a_is_snan  : std_logic;
    signal a_is_qnan  : std_logic;
    signal fclass_mask: std_logic_vector(9 downto 0);
begin

    a_sign     <= a(63);
    a_exp      <= a(62 downto 52);
    a_mant     <= a(51 downto 0);
    a_exp_zero <= '1' when a_exp = "00000000000" else '0';
    a_exp_max  <= '1' when a_exp = "11111111111" else '0';
    a_mant_zero<= '1' when a_mant = (51 downto 0 => '0') else '0';
    a_is_snan  <= a_exp_max and (not a_mant_zero) and (not a_mant(51));
    a_is_qnan  <= a_exp_max and a_mant(51);

    -- FCLASS bit-mask
    process(all)
    begin
        fclass_mask <= (others => '0');
        if a_sign = '1' and a_exp_max = '1' and a_mant_zero = '1' then
            fclass_mask(0) <= '1'; -- -Inf
        elsif a_sign = '1' and a_exp_zero = '0' and a_exp_max = '0' then
            fclass_mask(1) <= '1'; -- -normal
        elsif a_sign = '1' and a_exp_zero = '1' and a_mant_zero = '0' then
            fclass_mask(2) <= '1'; -- -subnormal
        elsif a_sign = '1' and a_exp_zero = '1' and a_mant_zero = '1' then
            fclass_mask(3) <= '1'; -- -0
        elsif a_sign = '0' and a_exp_zero = '1' and a_mant_zero = '1' then
            fclass_mask(4) <= '1'; -- +0
        elsif a_sign = '0' and a_exp_zero = '1' and a_mant_zero = '0' then
            fclass_mask(5) <= '1'; -- +subnormal
        elsif a_sign = '0' and a_exp_zero = '0' and a_exp_max = '0' then
            fclass_mask(6) <= '1'; -- +normal
        elsif a_sign = '0' and a_exp_max = '1' and a_mant_zero = '1' then
            fclass_mask(7) <= '1'; -- +Inf
        elsif a_is_snan = '1' then
            fclass_mask(8) <= '1'; -- sNaN
        elsif a_is_qnan = '1' then
            fclass_mask(9) <= '1'; -- qNaN
        end if;
    end process;

    -- Output mux
    process(all)
    begin
        result <= (others => '0');
        case op is
            when "000" =>
                result <= b(63) & a(62 downto 0);          -- FSGNJ.D
            when "001" =>
                result <= (not b(63)) & a(62 downto 0);    -- FSGNJN.D
            when "010" =>
                result <= (a(63) xor b(63)) & a(62 downto 0); -- FSGNJX.D
            when "011" =>
                result <= (63 downto 10 => '0') & fclass_mask; -- FCLASS.D
            when others =>
                result <= (others => '0');
        end case;
    end process;

    result_is_int <= '1' when op = "011" else '0';

end architecture rtl;
