library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_div is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        a      : in  std_logic_vector(63 downto 0);
        b      : in  std_logic_vector(63 downto 0);
        rm     : in  std_logic_vector(2 downto 0);
        result : out std_logic_vector(63 downto 0);
        flags  : out std_logic_vector(4 downto 0);
        done   : out std_logic;
        busy   : out std_logic
    );
end entity fp_div;

architecture rtl of fp_div is
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";
    constant EXP_MAX   : unsigned(10 downto 0) := "11111111111";
    constant EXP_BIAS  : unsigned(10 downto 0) := to_unsigned(1023, 11);
    constant NV : natural := 4; constant DZ_C : natural := 3;
    constant OF_C : natural := 2; constant UF_C : natural := 1; constant NX_C : natural := 0;

    type state_type is (S_IDLE, S_ITERATE, S_FINISH);
    signal state : state_type;

    signal a_sign_r, b_sign_r : std_logic;
    signal a_exp_r, b_exp_r   : unsigned(10 downto 0);
    signal a_mant_r, b_mant_r : unsigned(52 downto 0);
    signal a_is_nan_r, b_is_nan_r : std_logic;
    signal a_is_snan_r, b_is_snan_r : std_logic;
    signal a_is_inf_r, b_is_inf_r : std_logic;
    signal a_is_zero_r, b_is_zero_r : std_logic;
    signal a_is_sub_r, b_is_sub_r : std_logic;
    signal res_sign_r : std_logic;
    signal res_exp : signed(12 downto 0);
    signal quotient_r : unsigned(56 downto 0);
    signal partial_rem_r : signed(56 downto 0);
    signal divisor_r : unsigned(54 downto 0);
    signal iter_count : unsigned(5 downto 0);
    signal special_case_r : std_logic;
    signal special_result_r : std_logic_vector(63 downto 0);
    signal special_flags_r : std_logic_vector(4 downto 0);
    signal round_up_s : std_logic;
    signal r_guard, r_round, r_sticky, r_lsb, r_sign : std_logic;
    signal r_rm : std_logic_vector(2 downto 0);
    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r : std_logic_vector(4 downto 0);
    signal done_r, busy_r : std_logic;
begin

    u_round: entity work.fp_round
        port map (sign => r_sign, guard => r_guard, round_bit => r_round,
                  sticky => r_sticky, lsb => r_lsb, rm => r_rm, round_up => round_up_s);

    process(clk)
        variable q_final   : unsigned(56 downto 0);
        variable rem_final  : signed(56 downto 0);
        variable exp_final  : signed(12 downto 0);
        variable mant_final : unsigned(52 downto 0);
        variable g_bit, r_bit_v, s_bit : std_logic;
        variable mant_rounded : unsigned(52 downto 0);
        variable inexact : std_logic;
        variable new_rem : signed(56 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE; done_r <= '0'; busy_r <= '0';
                result_r <= (others => '0'); flags_r <= (others => '0');
                iter_count <= (others => '0');
                quotient_r <= (others => '0'); partial_rem_r <= (others => '0');
            else
                done_r <= '0';
                case state is
                    when S_IDLE =>
                        if start = '1' then
                            a_sign_r <= a(63); b_sign_r <= b(63);
                            a_exp_r <= unsigned(a(62 downto 52)); b_exp_r <= unsigned(b(62 downto 52));
                            if unsigned(a(62 downto 52)) = 0 then a_mant_r <= unsigned('0' & a(51 downto 0));
                            else a_mant_r <= unsigned('1' & a(51 downto 0)); end if;
                            if unsigned(b(62 downto 52)) = 0 then b_mant_r <= unsigned('0' & b(51 downto 0));
                            else b_mant_r <= unsigned('1' & b(51 downto 0)); end if;
                            a_is_nan_r  <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) /= 0 else '0';
                            b_is_nan_r  <= '1' when unsigned(b(62 downto 52)) = EXP_MAX and unsigned(b(51 downto 0)) /= 0 else '0';
                            a_is_snan_r <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) /= 0 and a(51) = '0' else '0';
                            b_is_snan_r <= '1' when unsigned(b(62 downto 52)) = EXP_MAX and unsigned(b(51 downto 0)) /= 0 and b(51) = '0' else '0';
                            a_is_inf_r  <= '1' when unsigned(a(62 downto 52)) = EXP_MAX and unsigned(a(51 downto 0)) = 0 else '0';
                            b_is_inf_r  <= '1' when unsigned(b(62 downto 52)) = EXP_MAX and unsigned(b(51 downto 0)) = 0 else '0';
                            a_is_zero_r <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) = 0 else '0';
                            b_is_zero_r <= '1' when unsigned(b(62 downto 52)) = 0 and unsigned(b(51 downto 0)) = 0 else '0';
                            a_is_sub_r  <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) /= 0 else '0';
                            b_is_sub_r  <= '1' when unsigned(b(62 downto 52)) = 0 and unsigned(b(51 downto 0)) /= 0 else '0';
                            res_sign_r <= a(63) xor b(63);
                            busy_r <= '1'; state <= S_ITERATE; iter_count <= to_unsigned(57, 6);
                            quotient_r <= (others => '0'); partial_rem_r <= (others => '0');
                        end if;

                    when S_ITERATE =>
                        if iter_count = 57 then
                            special_case_r <= '0'; special_result_r <= (others => '0'); special_flags_r <= (others => '0');
                            if a_is_nan_r = '1' or b_is_nan_r = '1' then
                                special_case_r <= '1'; special_result_r <= CANON_NAN;
                                if a_is_snan_r = '1' or b_is_snan_r = '1' then special_flags_r(NV) <= '1'; end if;
                            elsif a_is_inf_r = '1' and b_is_inf_r = '1' then
                                special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r(NV) <= '1';
                            elsif a_is_zero_r = '1' and b_is_zero_r = '1' then
                                special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r(NV) <= '1';
                            elsif a_is_inf_r = '1' then
                                special_case_r <= '1'; special_result_r <= res_sign_r & std_logic_vector(EXP_MAX) & (51 downto 0 => '0');
                            elsif b_is_zero_r = '1' then
                                special_case_r <= '1'; special_result_r <= res_sign_r & std_logic_vector(EXP_MAX) & (51 downto 0 => '0');
                                special_flags_r(DZ_C) <= '1';
                            elsif a_is_zero_r = '1' or b_is_inf_r = '1' then
                                special_case_r <= '1'; special_result_r <= res_sign_r & (62 downto 0 => '0');
                            end if;
                            if not (a_is_nan_r = '1' or b_is_nan_r = '1' or
                                    (a_is_inf_r = '1' and b_is_inf_r = '1') or
                                    (a_is_zero_r = '1' and b_is_zero_r = '1') or
                                    a_is_inf_r = '1' or b_is_zero_r = '1' or
                                    a_is_zero_r = '1' or b_is_inf_r = '1') then
                                if a_is_sub_r = '0' and b_is_sub_r = '0' then
                                    res_exp <= signed(resize(a_exp_r, 13)) - signed(resize(b_exp_r, 13)) + to_signed(1023, 13);
                                elsif a_is_sub_r = '0' and b_is_sub_r = '1' then
                                    res_exp <= signed(resize(a_exp_r, 13)) - to_signed(1, 13) + to_signed(1023, 13);
                                elsif a_is_sub_r = '1' and b_is_sub_r = '0' then
                                    res_exp <= to_signed(1, 13) - signed(resize(b_exp_r, 13)) + to_signed(1023, 13);
                                else
                                    res_exp <= to_signed(1, 13) - to_signed(1, 13) + to_signed(1023, 13);
                                end if;
                                partial_rem_r <= signed("0000" & a_mant_r);
                                divisor_r <= "00" & b_mant_r;
                                iter_count <= to_unsigned(56, 6);
                            else
                                iter_count <= (others => '0');
                            end if;
                        elsif iter_count = 0 then
                            state <= S_FINISH;
                        else
                            if partial_rem_r(56) = '0' then
                                quotient_r <= quotient_r(55 downto 0) & '1';
                                partial_rem_r <= shift_left(partial_rem_r, 1) - signed("00" & divisor_r);
                            else
                                quotient_r <= quotient_r(55 downto 0) & '0';
                                partial_rem_r <= shift_left(partial_rem_r, 1) + signed("00" & divisor_r);
                            end if;
                            iter_count <= iter_count - 1;
                        end if;

                    when S_FINISH =>
                        if special_case_r = '1' then
                            result_r <= special_result_r; flags_r <= special_flags_r;
                        else
                            if partial_rem_r(56) = '1' then
                                q_final := quotient_r - 1;
                                rem_final := partial_rem_r + signed("00" & divisor_r);
                            else
                                q_final := quotient_r;
                                rem_final := partial_rem_r;
                            end if;
                            exp_final := res_exp;
                            if q_final(55) = '0' then
                                q_final := shift_left(q_final, 1);
                                exp_final := exp_final - 1;
                            end if;
                            mant_final := q_final(55) & q_final(54 downto 3);
                            g_bit := q_final(2); r_bit_v := q_final(1);
                            if rem_final /= 0 then
                                s_bit := q_final(0) or '1';
                            else
                                s_bit := q_final(0);
                            end if;
                            r_sign <= res_sign_r; r_guard <= g_bit; r_round <= r_bit_v;
                            r_sticky <= s_bit; r_lsb <= q_final(3); r_rm <= rm;
                            inexact := g_bit or r_bit_v or s_bit;
                            mant_rounded := mant_final + (resize(unsigned'(0 => round_up_s), 53));
                            if mant_rounded(52) = '1' and mant_final(52) = '0' then
                                exp_final := exp_final + 1;
                            elsif mant_rounded = 0 and round_up_s = '1' then
                                exp_final := exp_final + 1;
                                mant_rounded := to_unsigned(1, 1) & to_unsigned(0, 52);
                            end if;
                            if exp_final >= 2047 then
                                result_r <= res_sign_r & std_logic_vector(EXP_MAX) & (51 downto 0 => '0');
                                flags_r <= "00101";
                            elsif exp_final <= 0 then
                                result_r <= res_sign_r & (62 downto 0 => '0');
                                flags_r <= "00011";
                            else
                                result_r <= res_sign_r & std_logic_vector(unsigned(exp_final(10 downto 0))) & std_logic_vector(mant_rounded(51 downto 0));
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
