library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_sqrt is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        a      : in  std_logic_vector(63 downto 0);
        rm     : in  std_logic_vector(2 downto 0);
        result : out std_logic_vector(63 downto 0);
        flags  : out std_logic_vector(4 downto 0);
        done   : out std_logic;
        busy   : out std_logic
    );
end entity fp_sqrt;

architecture rtl of fp_sqrt is
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";
    constant EXP_MAX   : unsigned(10 downto 0) := "11111111111";
    constant NV : natural := 4; constant DZ_C : natural := 3;
    constant OF_C : natural := 2; constant UF_C : natural := 1; constant NX_C : natural := 0;

    type state_type is (S_IDLE, S_ITERATE, S_FINISH);
    signal state : state_type;

    signal a_sign_r : std_logic;
    signal a_exp_r  : unsigned(10 downto 0);
    signal a_mant_r : unsigned(52 downto 0);
    signal a_is_nan_r, a_is_snan_r, a_is_inf_r, a_is_zero_r, a_is_sub_r : std_logic;
    signal res_exp     : signed(12 downto 0);
    signal remainder_r : unsigned(113 downto 0);
    signal root_r      : unsigned(56 downto 0);
    signal iter_count  : unsigned(5 downto 0);
    signal special_case_r : std_logic;
    signal special_result_r : std_logic_vector(63 downto 0);
    signal special_flags_r  : std_logic_vector(4 downto 0);
    signal round_up_s : std_logic;
    signal r_guard, r_round, r_sticky, r_lsb, r_sign : std_logic;
    signal r_rm : std_logic_vector(2 downto 0);
    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);
    signal done_r, busy_r : std_logic;
begin

    u_round: entity work.fp_round
        port map (sign => r_sign, guard => r_guard, round_bit => r_round,
                  sticky => r_sticky, lsb => r_lsb, rm => r_rm, round_up => round_up_s);

    process(clk)
        variable q : unsigned(55 downto 0);
        variable exp_final : signed(12 downto 0);
        variable mant_final : unsigned(52 downto 0);
        variable g_bit, r_bit_v, s_bit : std_logic;
        variable mant_rounded : unsigned(52 downto 0);
        variable inexact : std_logic;
        variable trial : unsigned(113 downto 0);
        variable eff_exp : unsigned(10 downto 0);
        variable mant_shifted : unsigned(53 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE; done_r <= '0'; busy_r <= '0';
                result_r <= (others => '0'); flags_r <= (others => '0');
                iter_count <= (others => '0');
                root_r <= (others => '0'); remainder_r <= (others => '0');
            else
                done_r <= '0';
                case state is
                    when S_IDLE =>
                        if start = '1' then
                            a_sign_r <= a(63); a_exp_r <= unsigned(a(62 downto 52));
                            if unsigned(a(62 downto 52)) = 0 then a_mant_r <= unsigned('0' & a(51 downto 0));
                            else a_mant_r <= unsigned('1' & a(51 downto 0)); end if;
                            a_is_nan_r  <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) /= 0 else '0';
                            a_is_snan_r <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) /= 0 and a(51) = '0' else '0';
                            a_is_inf_r  <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_zero_r <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_sub_r  <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) /= 0 else '0';
                            busy_r <= '1'; state <= S_ITERATE; iter_count <= to_unsigned(56, 6);
                            root_r <= (others => '0'); remainder_r <= (others => '0');
                        end if;

                    when S_ITERATE =>
                        if iter_count = 56 then
                            special_case_r <= '0'; special_result_r <= (others => '0'); special_flags_r <= (others => '0');
                            if a_is_nan_r = '1' then
                                special_case_r <= '1'; special_result_r <= CANON_NAN;
                                if a_is_snan_r = '1' then special_flags_r(NV) <= '1'; end if;
                            elsif a_sign_r = '1' and a_is_zero_r = '0' then
                                special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r(NV) <= '1';
                            elsif a_is_inf_r = '1' then
                                special_case_r <= '1'; special_result_r <= '0' & std_logic_vector(EXP_MAX) & (51 downto 0 => '0');
                            elsif a_is_zero_r = '1' then
                                special_case_r <= '1'; special_result_r <= a_sign_r & (62 downto 0 => '0');
                            end if;
                            if a_is_nan_r = '1' or (a_sign_r = '1' and a_is_zero_r = '0') or
                               a_is_inf_r = '1' or a_is_zero_r = '1' then
                                iter_count <= (others => '0');
                            else
                                if a_is_sub_r = '1' then eff_exp := to_unsigned(1, 11);
                                else eff_exp := a_exp_r; end if;
                                if eff_exp(0) = '1' then
                                    mant_shifted := a_mant_r & '0';
                                    res_exp <= (signed("00" & eff_exp) - 1) / 2 + 1023;
                                else
                                    mant_shifted := '0' & a_mant_r;
                                    res_exp <= signed("00" & eff_exp) / 2 + 511;
                                end if;
                                remainder_r <= unsigned(std_logic_vector(mant_shifted)) & (59 downto 0 => '0');
                                iter_count <= to_unsigned(55, 6);
                            end if;
                        elsif iter_count = 0 then
                            state <= S_FINISH;
                        else
                            trial := shift_left(resize(root_r & '1', 114), to_integer(iter_count - 1));
                            if remainder_r >= trial then
                                remainder_r <= remainder_r - trial;
                                root_r <= root_r(55 downto 0) & '1';
                            else
                                root_r <= root_r(55 downto 0) & '0';
                            end if;
                            iter_count <= iter_count - 1;
                        end if;

                    when S_FINISH =>
                        if special_case_r = '1' then
                            result_r <= special_result_r; flags_r <= special_flags_r;
                        else
                            q := root_r(55 downto 0);
                            exp_final := res_exp;
                            if q(54) = '0' then
                                q := shift_left(q, 1);
                                exp_final := exp_final - 1;
                            end if;
                            mant_final := q(54) & q(53 downto 2);
                            g_bit := q(1); r_bit_v := q(0);
                            s_bit := '1' when remainder_r /= 0 else '0';
                            r_sign <= '0'; r_guard <= g_bit; r_round <= r_bit_v;
                            r_sticky <= s_bit; r_lsb <= q(2); r_rm <= rm;
                            inexact := g_bit or r_bit_v or s_bit;
                            mant_rounded := mant_final + resize(unsigned'(0 => round_up_s), 53);
                            if mant_rounded(52) = '1' and mant_final(52) = '0' then
                                exp_final := exp_final + 1;
                            end if;
                            if exp_final >= 2047 then
                                result_r <= '0' & std_logic_vector(EXP_MAX) & (51 downto 0 => '0');
                                flags_r <= "00101";
                            elsif exp_final <= 0 then
                                result_r <= (others => '0');
                                flags_r <= "00011";
                            else
                                result_r <= '0' & std_logic_vector(unsigned(exp_final(10 downto 0))) & std_logic_vector(mant_rounded(51 downto 0));
                                flags_r <= (NX_C => inexact, others => '0');
                            end if;
                        end if;
                        done_r <= '1'; busy_r <= '0'; state <= S_IDLE;
                end case;
            end if;
        end if;
    end process;

    result <= result_r; flags <= flags_r; done <= done_r; busy <= busy_r;
end architecture rtl;
