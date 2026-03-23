library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_conv is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        start         : in  std_logic;
        op            : in  std_logic_vector(3 downto 0);
        fp_in         : in  std_logic_vector(63 downto 0);
        int_in        : in  std_logic_vector(63 downto 0);
        rm            : in  std_logic_vector(2 downto 0);
        result        : out std_logic_vector(63 downto 0);
        flags         : out std_logic_vector(4 downto 0);
        done          : out std_logic;
        busy          : out std_logic;
        result_is_int : out std_logic
    );
end entity fp_conv;

architecture rtl of fp_conv is
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";
    constant EXP_MAX   : unsigned(10 downto 0) := "11111111111";
    constant NV : natural := 4; constant NX_C : natural := 0;

    type state_type is (S_IDLE, S_CYCLE1, S_CYCLE2);
    signal state : state_type;

    signal lzc_data_s  : std_logic_vector(63 downto 0);
    signal lzc_count_s : std_logic_vector(6 downto 0);
    signal lzc_zero_s  : std_logic;
    signal round_up_s  : std_logic;
    signal r_guard, r_round, r_sticky, r_lsb, r_sign : std_logic;
    signal r_rm : std_logic_vector(2 downto 0);

    signal op_r : std_logic_vector(3 downto 0);
    signal rm_r : std_logic_vector(2 downto 0);
    signal fp_sign   : std_logic;
    signal fp_exp    : unsigned(10 downto 0);
    signal fp_mant   : unsigned(52 downto 0);
    signal fp_is_nan, fp_is_inf, fp_is_zero : std_logic;
    signal shift_amt : signed(12 downto 0);
    signal int_sign  : std_logic;
    signal int_abs   : unsigned(63 downto 0);

    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);
    signal done_r, busy_r : std_logic;
    signal result_is_int_r : std_logic;
begin

    u_lzc: entity work.fp_lzc
        port map (data => lzc_data_s, count => lzc_count_s, zero => lzc_zero_s);
    u_round: entity work.fp_round
        port map (sign => r_sign, guard => r_guard, round_bit => r_round,
                  sticky => r_sticky, lsb => r_lsb, rm => r_rm, round_up => round_up_s);

    process(clk)
        variable int_val : unsigned(63 downto 0);
        variable out_of_range, inexact_v : std_logic;
        variable max_pos, max_neg : unsigned(63 downto 0);
        variable shft : signed(12 downto 0);
        variable shifted_mant : unsigned(63 downto 0);
        variable frac_bits : unsigned(63 downto 0);
        variable abs_val : unsigned(63 downto 0);
        variable lz : unsigned(6 downto 0);
        variable exp_val : unsigned(10 downto 0);
        variable shifted_v : unsigned(63 downto 0);
        variable g_bit, rnd_bit, s_bit : std_logic;
        variable mant_out : unsigned(51 downto 0);
        variable mant_rounded : unsigned(52 downto 0);
        variable inexact_i : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE; done_r <= '0'; busy_r <= '0';
                result_r <= (others => '0'); flags_r <= (others => '0');
                result_is_int_r <= '0';
            else
                done_r <= '0';
                case state is
                    when S_IDLE =>
                        if start = '1' then
                            op_r <= op; rm_r <= rm;
                            if op = x"8" then
                                result_r <= fp_in; flags_r <= (others => '0');
                                result_is_int_r <= '1'; done_r <= '1';
                            elsif op = x"9" then
                                result_r <= int_in; flags_r <= (others => '0');
                                result_is_int_r <= '0'; done_r <= '1';
                            else
                                busy_r <= '1'; state <= S_CYCLE1;
                                if unsigned(op) <= 3 then
                                    fp_sign <= fp_in(63); fp_exp <= unsigned(fp_in(62 downto 52));
                                    if unsigned(fp_in(62 downto 52)) = 0 then
                                        fp_mant <= unsigned('0' & fp_in(51 downto 0));
                                    else
                                        fp_mant <= unsigned('1' & fp_in(51 downto 0));
                                    end if;
                                    fp_is_nan  <= '1' when unsigned(fp_in(62 downto 52)) = EXP_MAX and unsigned(fp_in(51 downto 0)) /= 0 else '0';
                                    fp_is_inf  <= '1' when unsigned(fp_in(62 downto 52)) = EXP_MAX and unsigned(fp_in(51 downto 0)) = 0 else '0';
                                    fp_is_zero <= '1' when unsigned(fp_in(62 downto 52)) = 0 and unsigned(fp_in(51 downto 0)) = 0 else '0';
                                    result_is_int_r <= '1';
                                else
                                    result_is_int_r <= '0';
                                    case op is
                                        when x"4" =>
                                            int_sign <= int_in(31);
                                            if int_in(31) = '1' then int_abs <= resize(unsigned(not int_in(31 downto 0)) + 1, 64);
                                            else int_abs <= resize(unsigned(int_in(31 downto 0)), 64); end if;
                                        when x"5" =>
                                            int_sign <= '0'; int_abs <= resize(unsigned(int_in(31 downto 0)), 64);
                                        when x"6" =>
                                            int_sign <= int_in(63);
                                            if int_in(63) = '1' then int_abs <= unsigned(not int_in) + 1;
                                            else int_abs <= unsigned(int_in); end if;
                                        when x"7" =>
                                            int_sign <= '0'; int_abs <= unsigned(int_in);
                                        when others =>
                                            int_sign <= '0'; int_abs <= (others => '0');
                                    end case;
                                end if;
                            end if;
                        end if;

                    when S_CYCLE1 =>
                        state <= S_CYCLE2;
                        if unsigned(op_r) <= 3 then
                            shift_amt <= signed(resize(fp_exp, 13)) - 1023;
                        else
                            lzc_data_s <= std_logic_vector(int_abs);
                        end if;

                    when S_CYCLE2 =>
                        flags_r <= (others => '0');
                        if unsigned(op_r) <= 3 then
                            -- FP -> Int
                            out_of_range := '0'; inexact_v := '0';
                            int_val := (others => '0');
                            shft := shift_amt;
                            case op_r is
                                when x"0" => max_pos := x"000000007FFFFFFF"; max_neg := x"FFFFFFFF80000000";
                                when x"1" => max_pos := x"00000000FFFFFFFF"; max_neg := (others => '0');
                                when x"2" => max_pos := x"7FFFFFFFFFFFFFFF"; max_neg := x"8000000000000000";
                                when x"3" => max_pos := (others => '1'); max_neg := (others => '0');
                                when others => max_pos := (others => '0'); max_neg := (others => '0');
                            end case;
                            if fp_is_nan = '1' or fp_is_inf = '1' then
                                out_of_range := '1';
                                if fp_is_nan = '1' or fp_sign = '0' then int_val := max_pos;
                                else int_val := max_neg; end if;
                            elsif fp_is_zero = '1' then
                                int_val := (others => '0');
                            elsif shft < 0 then
                                int_val := (others => '0'); inexact_v := '1';
                                r_sign <= fp_sign; r_lsb <= '0'; r_rm <= rm_r;
                                if shft = -1 then r_guard <= fp_mant(52); else r_guard <= '0'; end if;
                                r_round <= '0'; r_sticky <= '1';
                                if round_up_s = '1' then
                                    int_val := to_unsigned(1, 64);
                                    if fp_sign = '1' and (op_r = x"1" or op_r = x"3") then
                                        out_of_range := '1'; int_val := max_neg;
                                    end if;
                                end if;
                            elsif shft > 63 then
                                out_of_range := '1';
                                if fp_sign = '1' then int_val := max_neg; else int_val := max_pos; end if;
                            else
                                if shft >= 52 then
                                    shifted_mant := resize(fp_mant, 64);
                                    shifted_mant := shift_left(shifted_mant, to_integer(shft - 52));
                                    inexact_v := '0';
                                else
                                    shifted_mant := shift_right(resize(fp_mant, 64), to_integer(52 - shft));
                                    frac_bits := shift_left(resize(fp_mant, 64), to_integer(shft + 12));
                                    r_sign <= fp_sign; r_guard <= frac_bits(63);
                                    r_round <= frac_bits(62);
                                    r_sticky <= '1' when frac_bits(61 downto 0) /= 0 else '0';
                                    r_lsb <= shifted_mant(0); r_rm <= rm_r;
                                    if frac_bits(61 downto 0) /= 0 then
                                        inexact_v := '1';
                                    else
                                        inexact_v := frac_bits(63) or frac_bits(62);
                                    end if;
                                    shifted_mant := shifted_mant + resize(unsigned'(0 => round_up_s), 64);
                                end if;
                                int_val := shifted_mant;
                                if fp_sign = '1' then
                                    if op_r = x"1" or op_r = x"3" then
                                        if int_val /= 0 then out_of_range := '1'; int_val := max_neg; end if;
                                    else
                                        int_val := unsigned(-signed(int_val));
                                    end if;
                                end if;
                                if out_of_range = '0' then
                                    case op_r is
                                        when x"0" =>
                                            if fp_sign = '0' and shifted_mant > x"000000007FFFFFFF" then
                                                out_of_range := '1'; int_val := max_pos;
                                            elsif fp_sign = '1' and shifted_mant > x"0000000080000000" then
                                                out_of_range := '1'; int_val := max_neg;
                                            end if;
                                            if out_of_range = '0' then
                                                int_val := unsigned(resize(signed(int_val(31 downto 0)), 64));
                                            end if;
                                        when x"1" =>
                                            if shifted_mant > x"00000000FFFFFFFF" then
                                                out_of_range := '1'; int_val := max_pos;
                                            end if;
                                            if out_of_range = '0' then
                                                int_val := unsigned(resize(signed(int_val(31 downto 0)), 64));
                                            end if;
                                        when x"2" =>
                                            if fp_sign = '0' and shifted_mant > x"7FFFFFFFFFFFFFFF" then
                                                out_of_range := '1'; int_val := max_pos;
                                            end if;
                                        when others => null;
                                    end case;
                                end if;
                            end if;
                            result_r <= std_logic_vector(int_val);
                            if out_of_range = '1' then flags_r(NV) <= '1';
                            elsif inexact_v = '1' then flags_r(NX_C) <= '1'; end if;
                        else
                            -- Int -> FP
                            abs_val := int_abs;
                            lz := unsigned(lzc_count_s);
                            lzc_data_s <= std_logic_vector(abs_val);
                            if abs_val = 0 then
                                result_r <= int_sign & (62 downto 0 => '0');
                                flags_r <= (others => '0');
                            else
                                exp_val := to_unsigned(1086, 11) - resize(lz, 11);
                                shifted_v := shift_left(abs_val, to_integer(lz));
                                mant_out := shifted_v(62 downto 11);
                                g_bit := shifted_v(10); rnd_bit := shifted_v(9);
                                s_bit := '1' when shifted_v(8 downto 0) /= 0 else '0';
                                inexact_i := g_bit or rnd_bit or s_bit;
                                if op_r = x"4" or op_r = x"5" then
                                    inexact_i := '0'; g_bit := '0'; rnd_bit := '0'; s_bit := '0';
                                end if;
                                r_sign <= int_sign; r_guard <= g_bit; r_round <= rnd_bit;
                                r_sticky <= s_bit; r_lsb <= shifted_v(11); r_rm <= rm_r;
                                mant_rounded := ('0' & mant_out) + resize(unsigned'(0 => round_up_s), 53);
                                if mant_rounded(52) = '1' then
                                    exp_val := exp_val + 1;
                                    mant_out := mant_rounded(52 downto 1);
                                else
                                    mant_out := mant_rounded(51 downto 0);
                                end if;
                                result_r <= int_sign & std_logic_vector(exp_val) & std_logic_vector(mant_out);
                                if inexact_i = '1' then flags_r(NX_C) <= '1';
                                else flags_r <= (others => '0'); end if;
                            end if;
                        end if;
                        done_r <= '1'; busy_r <= '0'; state <= S_IDLE;
                end case;
            end if;
        end if;
    end process;

    result <= result_r; flags <= flags_r; done <= done_r; busy <= busy_r;
    result_is_int <= result_is_int_r;
end architecture rtl;
