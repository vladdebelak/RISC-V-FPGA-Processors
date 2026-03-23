library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_fma is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        op     : in  std_logic_vector(1 downto 0);
        a      : in  std_logic_vector(63 downto 0);
        b      : in  std_logic_vector(63 downto 0);
        c      : in  std_logic_vector(63 downto 0);
        rm     : in  std_logic_vector(2 downto 0);
        result : out std_logic_vector(63 downto 0);
        flags  : out std_logic_vector(4 downto 0);
        done   : out std_logic;
        busy   : out std_logic
    );
end entity fp_fma;

architecture rtl of fp_fma is
    type state_type is (IDLE, S1, S2, S3, S4);
    signal state : state_type;

    constant EXP_INF   : unsigned(10 downto 0) := "11111111111";
    constant BIAS      : unsigned(10 downto 0) := to_unsigned(1023, 11);
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";

    signal a_sign, b_sign, c_sign : std_logic;
    signal a_exp, b_exp, c_exp    : unsigned(10 downto 0);
    signal a_mant, b_mant, c_mant : unsigned(52 downto 0);
    signal a_is_zero, b_is_zero, c_is_zero : std_logic;
    signal a_is_inf, b_is_inf, c_is_inf    : std_logic;
    signal a_is_nan, b_is_nan, c_is_nan    : std_logic;
    signal a_is_snan, b_is_snan, c_is_snan : std_logic;
    signal a_is_sub, b_is_sub, c_is_sub    : std_logic;
    signal prod_sign_r, add_sign_r : std_logic;
    signal negate_prod_r, negate_c_r : std_logic;
    signal special_case_r : std_logic;
    signal special_result_r : std_logic_vector(63 downto 0);
    signal special_flags_r  : std_logic_vector(4 downto 0);
    signal product_r        : unsigned(105 downto 0);
    signal prod_exp_r       : signed(12 downto 0);
    signal c_exp_ext_r      : signed(12 downto 0);
    signal eff_sub_r        : std_logic;
    signal aligned_c_r      : unsigned(161 downto 0);
    signal align_sticky_r   : std_logic;
    signal result_exp_r     : signed(12 downto 0);
    signal sum_raw_r        : unsigned(161 downto 0);
    signal sum_sign_r       : std_logic;
    signal sum_exp_r        : signed(12 downto 0);
    signal sum_sticky_r     : std_logic;

    signal lzc_input_s : std_logic_vector(63 downto 0);
    signal lzc_count_s : std_logic_vector(6 downto 0);
    signal lzc_zero_s  : std_logic;
    signal rnd_sign_s, rnd_guard_s, rnd_round_s, rnd_sticky_s, rnd_lsb_s : std_logic;
    signal round_up_s : std_logic;
    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);
    signal done_r, busy_r : std_logic;
begin

    u_lzc: entity work.fp_lzc
        port map (data => lzc_input_s, count => lzc_count_s, zero => lzc_zero_s);
    u_round: entity work.fp_round
        port map (sign => rnd_sign_s, guard => rnd_guard_s, round_bit => rnd_round_s,
                  sticky => rnd_sticky_s, lsb => rnd_lsb_s, rm => rm, round_up => round_up_s);

    lzc_input_s <= std_logic_vector(sum_raw_r(161 downto 98));

    process(clk)
        variable exp_delta : signed(12 downto 0);
        variable c_wide    : unsigned(161 downto 0);
        variable prod_wide : unsigned(161 downto 0);
        variable add_val   : unsigned(161 downto 0);
        variable raw_sum   : unsigned(161 downto 0);
        variable raw_sign  : std_logic;
        variable p_sticky  : std_logic;
        variable norm_sum  : unsigned(161 downto 0);
        variable norm_exp  : signed(12 downto 0);
        variable total_lz  : unsigned(6 downto 0);
        variable shift_left_v : signed(12 downto 0);
        variable max_shift : signed(12 downto 0);
        variable s4_guard, s4_round, s4_sticky : std_logic;
        variable final_mant : unsigned(51 downto 0);
        variable final_exp  : unsigned(10 downto 0);
        variable final_flags : std_logic_vector(4 downto 0);
        variable final_sign : std_logic;
        variable found_v   : boolean;
        variable ps, as    : std_logic;
        variable stk_v     : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE; result_r <= (others => '0'); flags_r <= (others => '0');
                done_r <= '0'; busy_r <= '0';
                a_sign <= '0'; b_sign <= '0'; c_sign <= '0';
                a_exp <= (others => '0'); b_exp <= (others => '0'); c_exp <= (others => '0');
                a_mant <= (others => '0'); b_mant <= (others => '0'); c_mant <= (others => '0');
                a_is_zero <= '0'; b_is_zero <= '0'; c_is_zero <= '0';
                a_is_inf <= '0'; b_is_inf <= '0'; c_is_inf <= '0';
                a_is_nan <= '0'; b_is_nan <= '0'; c_is_nan <= '0';
                a_is_snan <= '0'; b_is_snan <= '0'; c_is_snan <= '0';
                a_is_sub <= '0'; b_is_sub <= '0'; c_is_sub <= '0';
                prod_sign_r <= '0'; add_sign_r <= '0';
                negate_prod_r <= '0'; negate_c_r <= '0';
                special_case_r <= '0'; special_result_r <= (others => '0'); special_flags_r <= (others => '0');
                product_r <= (others => '0'); prod_exp_r <= (others => '0'); c_exp_ext_r <= (others => '0');
                eff_sub_r <= '0'; aligned_c_r <= (others => '0'); align_sticky_r <= '0';
                result_exp_r <= (others => '0');
                sum_raw_r <= (others => '0'); sum_sign_r <= '0'; sum_exp_r <= (others => '0'); sum_sticky_r <= '0';
            else
                done_r <= '0';
                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= S1; busy_r <= '1'; flags_r <= (others => '0');
                            negate_prod_r <= op(1); negate_c_r <= op(0);
                            a_sign <= a(63); a_exp <= unsigned(a(62 downto 52));
                            if unsigned(a(62 downto 52)) = 0 then a_mant <= unsigned('0' & a(51 downto 0));
                            else a_mant <= unsigned('1' & a(51 downto 0)); end if;
                            b_sign <= b(63); b_exp <= unsigned(b(62 downto 52));
                            if unsigned(b(62 downto 52)) = 0 then b_mant <= unsigned('0' & b(51 downto 0));
                            else b_mant <= unsigned('1' & b(51 downto 0)); end if;
                            c_sign <= c(63); c_exp <= unsigned(c(62 downto 52));
                            if unsigned(c(62 downto 52)) = 0 then c_mant <= unsigned('0' & c(51 downto 0));
                            else c_mant <= unsigned('1' & c(51 downto 0)); end if;
                            -- Classify
                            a_is_zero <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_sub  <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) /= 0 else '0';
                            a_is_inf  <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_nan  <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) /= 0 else '0';
                            a_is_snan <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) /= 0 and a(51) = '0' else '0';
                            b_is_zero <= '1' when unsigned(b(62 downto 52)) = 0 and unsigned(b(51 downto 0)) = 0 else '0';
                            b_is_sub  <= '1' when unsigned(b(62 downto 52)) = 0 and unsigned(b(51 downto 0)) /= 0 else '0';
                            b_is_inf  <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) = 0 else '0';
                            b_is_nan  <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) /= 0 else '0';
                            b_is_snan <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) /= 0 and b(51) = '0' else '0';
                            c_is_zero <= '1' when unsigned(c(62 downto 52)) = 0 and unsigned(c(51 downto 0)) = 0 else '0';
                            c_is_sub  <= '1' when unsigned(c(62 downto 52)) = 0 and unsigned(c(51 downto 0)) /= 0 else '0';
                            c_is_inf  <= '1' when unsigned(c(62 downto 52)) = EXP_INF and unsigned(c(51 downto 0)) = 0 else '0';
                            c_is_nan  <= '1' when unsigned(c(62 downto 52)) = EXP_INF and unsigned(c(51 downto 0)) /= 0 else '0';
                            c_is_snan <= '1' when unsigned(c(62 downto 52)) = EXP_INF and unsigned(c(51 downto 0)) /= 0 and c(51) = '0' else '0';
                        end if;

                    when S1 =>
                        prod_sign_r <= (a_sign xor b_sign) xor negate_prod_r;
                        add_sign_r  <= c_sign xor negate_c_r;
                        if a_is_nan = '1' or b_is_nan = '1' or c_is_nan = '1' then
                            special_case_r <= '1'; special_result_r <= CANON_NAN;
                            special_flags_r <= (4 => (a_is_snan or b_is_snan or c_is_snan), others => '0');
                        elsif (a_is_inf = '1' or b_is_inf = '1') and (a_is_zero = '1' or b_is_zero = '1') then
                            special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r <= "10000";
                        elsif (a_is_inf = '1' or b_is_inf = '1') and c_is_inf = '1' then
                            if ((a_sign xor b_sign) xor negate_prod_r) /= (c_sign xor negate_c_r) then
                                special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r <= "10000";
                            else
                                special_case_r <= '1';
                                special_result_r <= ((a_sign xor b_sign) xor negate_prod_r) & std_logic_vector(EXP_INF) & (51 downto 0 => '0');
                                special_flags_r <= (others => '0');
                            end if;
                        elsif a_is_inf = '1' or b_is_inf = '1' then
                            special_case_r <= '1';
                            special_result_r <= ((a_sign xor b_sign) xor negate_prod_r) & std_logic_vector(EXP_INF) & (51 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        elsif c_is_inf = '1' then
                            special_case_r <= '1';
                            special_result_r <= (c_sign xor negate_c_r) & std_logic_vector(EXP_INF) & (51 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        elsif (a_is_zero = '1' or b_is_zero = '1') and c_is_zero = '1' then
                            ps := (a_sign xor b_sign) xor negate_prod_r;
                            as := c_sign xor negate_c_r;
                            special_case_r <= '1';
                            if ps = as then special_result_r <= ps & (62 downto 0 => '0');
                            elsif rm = "010" then special_result_r <= '1' & (62 downto 0 => '0');
                            else special_result_r <= (others => '0'); end if;
                            special_flags_r <= (others => '0');
                        elsif a_is_zero = '1' or b_is_zero = '1' then
                            special_case_r <= '1';
                            special_result_r <= (c_sign xor negate_c_r) & std_logic_vector(c_exp) & std_logic_vector(c_mant(51 downto 0));
                            special_flags_r <= (others => '0');
                        else
                            special_case_r <= '0';
                        end if;
                        if a_is_sub = '0' and b_is_sub = '0' then
                            prod_exp_r <= signed("00" & a_exp) + signed("00" & b_exp) - signed("00" & BIAS);
                        elsif a_is_sub = '0' and b_is_sub = '1' then
                            prod_exp_r <= signed("00" & a_exp) + to_signed(1, 13) - signed("00" & BIAS);
                        elsif a_is_sub = '1' and b_is_sub = '0' then
                            prod_exp_r <= to_signed(1, 13) + signed("00" & b_exp) - signed("00" & BIAS);
                        else
                            prod_exp_r <= to_signed(1, 13) + to_signed(1, 13) - signed("00" & BIAS);
                        end if;
                        if c_is_sub = '0' then
                            c_exp_ext_r <= signed("00" & c_exp);
                        else
                            c_exp_ext_r <= to_signed(1, 13);
                        end if;
                        state <= S2;

                    when S2 =>
                        if special_case_r = '1' then
                            result_r <= special_result_r; flags_r <= special_flags_r;
                            done_r <= '1'; busy_r <= '0'; state <= IDLE;
                        else
                            product_r <= a_mant * b_mant;
                            eff_sub_r <= prod_sign_r xor add_sign_r;
                            exp_delta := prod_exp_r - c_exp_ext_r;
                            c_wide := (others => '0');
                            c_wide(108 downto 56) := c_mant;
                            if exp_delta >= 0 then
                                if exp_delta >= 162 then
                                    aligned_c_r <= (others => '0');
                                    align_sticky_r <= '1' when c_mant /= 0 else '0';
                                else
                                    aligned_c_r <= shift_right(c_wide, to_integer(exp_delta));
                                    stk_v := '0';
                                    for i in 0 to 161 loop
                                        if i < to_integer(exp_delta) then stk_v := stk_v or c_wide(i); end if;
                                    end loop;
                                    align_sticky_r <= stk_v;
                                end if;
                                result_exp_r <= prod_exp_r;
                            else
                                if (-exp_delta) >= 53 then
                                    aligned_c_r <= shift_left(c_wide, 53);
                                else
                                    aligned_c_r <= shift_left(c_wide, to_integer(-exp_delta));
                                end if;
                                align_sticky_r <= '0';
                                result_exp_r <= c_exp_ext_r;
                            end if;
                            state <= S3;
                        end if;

                    when S3 =>
                        prod_wide := (others => '0');
                        prod_wide(108 downto 3) := product_r;
                        exp_delta := prod_exp_r - c_exp_ext_r;
                        if exp_delta < 0 then
                            p_sticky := '0';
                            if (-exp_delta) < 162 then
                                for j in 0 to 161 loop
                                    if j < to_integer(-exp_delta) then p_sticky := p_sticky or prod_wide(j); end if;
                                end loop;
                                prod_wide := shift_right(prod_wide, to_integer(-exp_delta));
                                prod_wide(0) := prod_wide(0) or p_sticky;
                            else
                                prod_wide := (others => '0');
                                if product_r /= 0 then prod_wide(0) := '1'; end if;
                            end if;
                        end if;
                        add_val := aligned_c_r;
                        add_val(0) := add_val(0) or align_sticky_r;
                        if eff_sub_r = '0' then
                            raw_sum := prod_wide + add_val;
                            raw_sign := prod_sign_r;
                        else
                            if prod_wide >= add_val then
                                raw_sum := prod_wide - add_val; raw_sign := prod_sign_r;
                            else
                                raw_sum := add_val - prod_wide; raw_sign := add_sign_r;
                            end if;
                        end if;
                        sum_raw_r <= raw_sum; sum_sign_r <= raw_sign;
                        sum_exp_r <= result_exp_r; sum_sticky_r <= '0';
                        if raw_sum = 0 then
                            if rm = "010" then result_r <= '1' & (62 downto 0 => '0');
                            else result_r <= raw_sign & (62 downto 0 => '0'); end if;
                            flags_r <= (others => '0'); done_r <= '1'; busy_r <= '0'; state <= IDLE;
                        else
                            state <= S4;
                        end if;

                    when S4 =>
                        final_flags := (others => '0');
                        final_sign := sum_sign_r;
                        norm_sum := sum_raw_r; norm_exp := sum_exp_r;
                        if lzc_zero_s = '0' then
                            total_lz := unsigned(lzc_count_s);
                        else
                            total_lz := to_unsigned(64, 7);
                            found_v := false;
                            for k in 97 downto 0 loop
                                if not found_v and norm_sum(k) = '1' then
                                    total_lz := to_unsigned(161 - k, 7);
                                    found_v := true;
                                end if;
                            end loop;
                            if not found_v then total_lz := to_unsigned(127, 7); end if;
                        end if;
                        shift_left_v := resize(signed('0' & total_lz), 13);
                        max_shift := norm_exp + 1;
                        if max_shift < 0 then max_shift := to_signed(0, 13); end if;
                        if shift_left_v <= max_shift or max_shift > 127 then
                            if shift_left_v < 162 then norm_sum := shift_left(sum_raw_r, to_integer(shift_left_v));
                            else norm_sum := (others => '0'); end if;
                            norm_exp := norm_exp - shift_left_v + 1;
                        else
                            if max_shift > 0 and max_shift < 162 then
                                norm_sum := shift_left(sum_raw_r, to_integer(max_shift));
                            end if;
                            norm_exp := to_signed(0, 13);
                        end if;
                        final_mant := norm_sum(160 downto 109);
                        s4_guard := norm_sum(108); s4_round := norm_sum(107);
                        s4_sticky := '1' when norm_sum(106 downto 0) /= 0 else '0';
                        s4_sticky := s4_sticky or sum_sticky_r;
                        rnd_sign_s <= final_sign; rnd_guard_s <= s4_guard;
                        rnd_round_s <= s4_round; rnd_sticky_s <= s4_sticky; rnd_lsb_s <= final_mant(0);
                        if round_up_s = '1' then
                            final_mant := final_mant + 1;
                            if final_mant = 0 then norm_exp := norm_exp + 1; end if;
                        end if;
                        if norm_exp >= 2047 then
                            final_flags := final_flags or "00101";
                            case rm is
                                when "000" | "100" => final_exp := EXP_INF; final_mant := (others => '0');
                                when "001" => final_exp := "11111111110"; final_mant := (others => '1');
                                when "010" =>
                                    if final_sign = '1' then final_exp := EXP_INF; final_mant := (others => '0');
                                    else final_exp := "11111111110"; final_mant := (others => '1'); end if;
                                when "011" =>
                                    if final_sign = '1' then final_exp := "11111111110"; final_mant := (others => '1');
                                    else final_exp := EXP_INF; final_mant := (others => '0'); end if;
                                when others => final_exp := EXP_INF; final_mant := (others => '0');
                            end case;
                        elsif norm_exp <= 0 then
                            final_exp := (others => '0');
                            if s4_guard = '1' or s4_round = '1' or s4_sticky = '1' then
                                final_flags := final_flags or "00011";
                            end if;
                        else
                            final_exp := unsigned(norm_exp(10 downto 0));
                            if s4_guard = '1' or s4_round = '1' or s4_sticky = '1' then
                                final_flags := final_flags or "00001";
                            end if;
                        end if;
                        result_r <= final_sign & std_logic_vector(final_exp) & std_logic_vector(final_mant);
                        flags_r <= final_flags;
                        done_r <= '1'; busy_r <= '0'; state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    result <= result_r; flags <= flags_r; done <= done_r; busy <= busy_r;
end architecture rtl;
