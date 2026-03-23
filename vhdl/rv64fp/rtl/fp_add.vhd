library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_add is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        is_sub : in  std_logic;
        a      : in  std_logic_vector(63 downto 0);
        b      : in  std_logic_vector(63 downto 0);
        rm     : in  std_logic_vector(2 downto 0);
        result : out std_logic_vector(63 downto 0);
        flags  : out std_logic_vector(4 downto 0);
        done   : out std_logic;
        busy   : out std_logic
    );
end entity fp_add;

architecture rtl of fp_add is
    type state_type is (IDLE, STAGE1, STAGE2, STAGE3);
    signal state : state_type;

    constant EXP_INF   : unsigned(10 downto 0) := "11111111111";
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";

    -- Stage 1 registers
    signal a_sign, b_sign       : std_logic;
    signal a_exp, b_exp         : unsigned(10 downto 0);
    signal a_mant, b_mant       : unsigned(52 downto 0);
    signal a_is_zero, b_is_zero : std_logic;
    signal a_is_inf, b_is_inf   : std_logic;
    signal a_is_nan, b_is_nan   : std_logic;
    signal a_is_snan, b_is_snan : std_logic;
    signal a_is_sub_r, b_is_sub_norm : std_logic;
    signal eff_sub_r            : std_logic;
    signal swap_r               : std_logic;
    signal exp_diff_r           : unsigned(10 downto 0);
    signal res_exp_r            : unsigned(10 downto 0);
    signal res_sign_r           : std_logic;
    signal mant_large_r, mant_small_r : unsigned(52 downto 0);
    signal special_case_r       : std_logic;
    signal special_result_r     : std_logic_vector(63 downto 0);
    signal special_flags_r      : std_logic_vector(4 downto 0);

    -- Stage 2 registers
    signal sum_raw_r            : unsigned(54 downto 0);
    signal sum_sign_r           : std_logic;
    signal sum_exp_r            : unsigned(10 downto 0);
    signal guard_s2_r, round_s2_r, sticky_s2_r : std_logic;
    signal sum_is_zero_r        : std_logic;

    -- LZC
    signal lzc_input_s : std_logic_vector(63 downto 0);
    signal lzc_count_s : std_logic_vector(6 downto 0);
    signal lzc_zero_s  : std_logic;

    -- Rounding
    signal rnd_sign_s, rnd_guard_s, rnd_round_s, rnd_sticky_s, rnd_lsb_s : std_logic;
    signal round_up_s : std_logic;

    -- Alignment helper
    signal aligned_small_s : unsigned(54 downto 0);
    signal align_guard_s, align_round_s, align_sticky_s : std_logic;

    -- Internal output signals
    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);
    signal done_r   : std_logic;
    signal busy_r   : std_logic;
begin

    u_lzc: entity work.fp_lzc
        port map (data => lzc_input_s, count => lzc_count_s, zero => lzc_zero_s);

    u_round: entity work.fp_round
        port map (
            sign => rnd_sign_s, guard => rnd_guard_s, round_bit => rnd_round_s,
            sticky => rnd_sticky_s, lsb => rnd_lsb_s, rm => rm, round_up => round_up_s
        );

    -- LZC input
    lzc_input_s <= std_logic_vector(sum_raw_r) & "000000000";

    -- Alignment block (combinational)
    process(all)
        variable wide : unsigned(108 downto 0);
        variable wide_shifted : unsigned(108 downto 0);
        variable stk : std_logic;
    begin
        aligned_small_s <= (others => '0');
        align_guard_s   <= '0';
        align_round_s   <= '0';
        align_sticky_s  <= '0';

        if exp_diff_r = 0 then
            aligned_small_s <= "00" & mant_small_r;
        elsif exp_diff_r = 1 then
            aligned_small_s <= shift_right("00" & mant_small_r, 1);
            align_guard_s   <= mant_small_r(0);
        elsif exp_diff_r = 2 then
            aligned_small_s <= shift_right("00" & mant_small_r, 2);
            align_guard_s   <= mant_small_r(1);
            align_round_s   <= mant_small_r(0);
        elsif exp_diff_r <= 55 then
            wide := "00000000000000000000000000000000000000000000000000000" & mant_small_r & "000";
            wide_shifted := shift_right(wide, to_integer(exp_diff_r));
            aligned_small_s <= "00" & wide_shifted(55 downto 3);
            align_guard_s   <= wide_shifted(2);
            align_round_s   <= wide_shifted(1);
            stk := wide_shifted(0);
            for j in 0 to 52 loop
                if j < to_integer(exp_diff_r) - 3 and j < 53 then
                    stk := stk or mant_small_r(j);
                end if;
            end loop;
            align_sticky_s <= stk;
        else
            aligned_small_s <= (others => '0');
            align_sticky_s  <= '1' when mant_small_r /= 0 else '0';
        end if;
    end process;

    -- Main state machine
    process(clk)
        variable norm_mant   : unsigned(54 downto 0);
        variable norm_exp    : unsigned(10 downto 0);
        variable shift_amt   : unsigned(6 downto 0);
        variable s3_guard, s3_round, s3_sticky : std_logic;
        variable final_mant  : unsigned(51 downto 0);
        variable final_exp   : unsigned(10 downto 0);
        variable final_sign  : std_logic;
        variable final_flags : std_logic_vector(4 downto 0);
        variable overflow_v  : std_logic;
        variable underflow_v : std_logic;
        variable round_inc   : unsigned(65 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                result_r <= (others => '0');
                flags_r  <= (others => '0');
                done_r   <= '0';
                busy_r   <= '0';
                a_sign <= '0'; b_sign <= '0';
                a_exp <= (others => '0'); b_exp <= (others => '0');
                a_mant <= (others => '0'); b_mant <= (others => '0');
                a_is_zero <= '0'; b_is_zero <= '0';
                a_is_inf <= '0'; b_is_inf <= '0';
                a_is_nan <= '0'; b_is_nan <= '0';
                a_is_snan <= '0'; b_is_snan <= '0';
                eff_sub_r <= '0'; swap_r <= '0';
                exp_diff_r <= (others => '0'); res_exp_r <= (others => '0'); res_sign_r <= '0';
                mant_large_r <= (others => '0'); mant_small_r <= (others => '0');
                special_case_r <= '0'; special_result_r <= (others => '0'); special_flags_r <= (others => '0');
                sum_raw_r <= (others => '0'); sum_sign_r <= '0'; sum_exp_r <= (others => '0');
                guard_s2_r <= '0'; round_s2_r <= '0'; sticky_s2_r <= '0';
                sum_is_zero_r <= '0';
            else
                done_r <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= STAGE1;
                            busy_r <= '1';
                            flags_r <= (others => '0');
                            -- Unpack A
                            a_sign <= a(63);
                            a_exp  <= unsigned(a(62 downto 52));
                            if unsigned(a(62 downto 52)) = 0 then
                                a_mant <= unsigned('0' & a(51 downto 0));
                            else
                                a_mant <= unsigned('1' & a(51 downto 0));
                            end if;
                            -- Unpack B
                            b_sign <= b(63) xor is_sub;
                            b_exp  <= unsigned(b(62 downto 52));
                            if unsigned(b(62 downto 52)) = 0 then
                                b_mant <= unsigned('0' & b(51 downto 0));
                            else
                                b_mant <= unsigned('1' & b(51 downto 0));
                            end if;
                            -- Classify
                            a_is_zero <= '1' when unsigned(a(62 downto 52)) = 0 and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_inf  <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) = 0 else '0';
                            a_is_nan  <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) /= 0 else '0';
                            a_is_snan <= '1' when unsigned(a(62 downto 52)) = EXP_INF and unsigned(a(51 downto 0)) /= 0 and a(51) = '0' else '0';
                            b_is_zero <= '1' when unsigned(b(62 downto 52)) = 0 and unsigned(b(51 downto 0)) = 0 else '0';
                            b_is_inf  <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) = 0 else '0';
                            b_is_nan  <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) /= 0 else '0';
                            b_is_snan <= '1' when unsigned(b(62 downto 52)) = EXP_INF and unsigned(b(51 downto 0)) /= 0 and b(51) = '0' else '0';
                        end if;

                    when STAGE1 =>
                        eff_sub_r <= a_sign xor b_sign;
                        -- Special case handling
                        if a_is_nan = '1' or b_is_nan = '1' then
                            special_case_r <= '1';
                            special_result_r <= CANON_NAN;
                            special_flags_r <= (4 => (a_is_snan or b_is_snan), others => '0');
                        elsif a_is_inf = '1' and b_is_inf = '1' then
                            if a_sign = b_sign then
                                special_case_r <= '1';
                                special_result_r <= a_sign & "11111111111" & (51 downto 0 => '0');
                                special_flags_r <= (others => '0');
                            else
                                special_case_r <= '1';
                                special_result_r <= CANON_NAN;
                                special_flags_r <= "10000";
                            end if;
                        elsif a_is_inf = '1' then
                            special_case_r <= '1';
                            special_result_r <= a_sign & "11111111111" & (51 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        elsif b_is_inf = '1' then
                            special_case_r <= '1';
                            special_result_r <= b_sign & "11111111111" & (51 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        elsif a_is_zero = '1' and b_is_zero = '1' then
                            special_case_r <= '1';
                            if a_sign = b_sign then
                                special_result_r <= a_sign & (62 downto 0 => '0');
                            else
                                if rm = "010" then
                                    special_result_r <= '1' & (62 downto 0 => '0');
                                else
                                    special_result_r <= (others => '0');
                                end if;
                            end if;
                            special_flags_r <= (others => '0');
                        elsif a_is_zero = '1' then
                            special_case_r <= '1';
                            special_result_r <= b_sign & std_logic_vector(b_exp) & std_logic_vector(b_mant(51 downto 0));
                            special_flags_r <= (others => '0');
                        elsif b_is_zero = '1' then
                            special_case_r <= '1';
                            special_result_r <= a_sign & std_logic_vector(a_exp) & std_logic_vector(a_mant(51 downto 0));
                            special_flags_r <= (others => '0');
                        else
                            special_case_r <= '0';
                        end if;
                        -- Determine larger operand
                        if a_exp > b_exp or (a_exp = b_exp and a_mant >= b_mant) then
                            swap_r <= '0';
                            mant_large_r <= a_mant;
                            mant_small_r <= b_mant;
                            res_exp_r    <= a_exp;
                            res_sign_r   <= a_sign;
                            exp_diff_r   <= a_exp - b_exp;
                        else
                            swap_r <= '1';
                            mant_large_r <= b_mant;
                            mant_small_r <= a_mant;
                            res_exp_r    <= b_exp;
                            res_sign_r   <= b_sign;
                            exp_diff_r   <= b_exp - a_exp;
                        end if;
                        state <= STAGE2;

                    when STAGE2 =>
                        if special_case_r = '1' then
                            result_r <= special_result_r;
                            flags_r  <= special_flags_r;
                            done_r   <= '1';
                            busy_r   <= '0';
                            state    <= IDLE;
                        else
                            if (a_sign xor b_sign) = '0' then
                                sum_raw_r <= ("00" & mant_large_r) + aligned_small_s;
                                sum_sign_r <= res_sign_r;
                            else
                                sum_raw_r <= ("00" & mant_large_r) - aligned_small_s;
                                sum_sign_r <= res_sign_r;
                            end if;
                            sum_exp_r   <= res_exp_r;
                            guard_s2_r  <= align_guard_s;
                            round_s2_r  <= align_round_s;
                            sticky_s2_r <= align_sticky_s;
                            if ("00" & mant_large_r) = aligned_small_s and
                               align_guard_s = '0' and align_round_s = '0' and align_sticky_s = '0' and
                               (a_sign xor b_sign) = '1' then
                                sum_is_zero_r <= '1';
                            else
                                sum_is_zero_r <= '0';
                            end if;
                            state <= STAGE3;
                        end if;

                    when STAGE3 =>
                        final_flags := (others => '0');
                        overflow_v  := '0';
                        underflow_v := '0';

                        if sum_is_zero_r = '1' then
                            if rm = "010" then final_sign := '1'; else final_sign := '0'; end if;
                            final_exp  := (others => '0');
                            final_mant := (others => '0');
                            s3_guard := '0'; s3_round := '0'; s3_sticky := '0';
                        else
                            final_sign := sum_sign_r;
                            if sum_raw_r(54) = '1' then
                                norm_mant := shift_right(sum_raw_r, 1);
                                norm_exp  := sum_exp_r + 1;
                                s3_guard  := sum_raw_r(0);
                                s3_round  := guard_s2_r;
                                s3_sticky := round_s2_r or sticky_s2_r;
                            elsif sum_raw_r(53) = '1' then
                                norm_mant := sum_raw_r;
                                norm_exp  := sum_exp_r;
                                s3_guard  := guard_s2_r;
                                s3_round  := round_s2_r;
                                s3_sticky := sticky_s2_r;
                            else
                                shift_amt := unsigned(lzc_count_s);
                                if shift_amt <= 1 then
                                    shift_amt := (others => '0');
                                else
                                    shift_amt := shift_amt - 1;
                                end if;
                                if shift_amt >= resize(sum_exp_r, 7) then
                                    if sum_exp_r > 0 then
                                        norm_mant := shift_left(sum_raw_r, to_integer(sum_exp_r - 1));
                                        norm_exp := (others => '0');
                                    else
                                        norm_mant := sum_raw_r;
                                        norm_exp := (others => '0');
                                    end if;
                                    underflow_v := '1';
                                else
                                    norm_mant := shift_left(sum_raw_r, to_integer(shift_amt));
                                    norm_exp  := sum_exp_r - resize(shift_amt, 11);
                                end if;
                                s3_guard  := guard_s2_r;
                                s3_round  := round_s2_r;
                                s3_sticky := sticky_s2_r;
                            end if;

                            -- Rounding
                            rnd_sign_s   <= final_sign;
                            rnd_guard_s  <= s3_guard;
                            rnd_round_s  <= s3_round;
                            rnd_sticky_s <= s3_sticky;
                            rnd_lsb_s    <= norm_mant(0);

                            if round_up_s = '1' then
                                round_inc := resize(norm_exp, 11) & resize(norm_mant, 55);
                                round_inc := round_inc + 1;
                                norm_exp  := unsigned(round_inc(65 downto 55));
                                norm_mant := unsigned(round_inc(54 downto 0));
                                if norm_mant(54) = '1' then
                                    norm_mant := shift_right(norm_mant, 1);
                                    norm_exp  := norm_exp + 1;
                                end if;
                            end if;

                            -- Overflow
                            if norm_exp >= EXP_INF then
                                overflow_v := '1';
                                final_flags := final_flags or "00101";
                                case rm is
                                    when "000" | "100" =>
                                        final_exp := EXP_INF; final_mant := (others => '0');
                                    when "001" =>
                                        final_exp := "11111111110"; final_mant := (others => '1');
                                    when "010" =>
                                        if final_sign = '1' then
                                            final_exp := EXP_INF; final_mant := (others => '0');
                                        else
                                            final_exp := "11111111110"; final_mant := (others => '1');
                                        end if;
                                    when "011" =>
                                        if final_sign = '1' then
                                            final_exp := "11111111110"; final_mant := (others => '1');
                                        else
                                            final_exp := EXP_INF; final_mant := (others => '0');
                                        end if;
                                    when others =>
                                        final_exp := EXP_INF; final_mant := (others => '0');
                                end case;
                            elsif norm_exp = 0 then
                                final_exp  := (others => '0');
                                final_mant := norm_mant(51 downto 0);
                                if s3_guard = '1' or s3_round = '1' or s3_sticky = '1' then
                                    final_flags := final_flags or "00011";
                                end if;
                            else
                                final_exp  := norm_exp;
                                final_mant := norm_mant(51 downto 0);
                                if s3_guard = '1' or s3_round = '1' or s3_sticky = '1' then
                                    final_flags := final_flags or "00001";
                                end if;
                            end if;
                        end if;

                        result_r <= final_sign & std_logic_vector(final_exp) & std_logic_vector(final_mant);
                        flags_r  <= final_flags;
                        done_r   <= '1';
                        busy_r   <= '0';
                        state    <= IDLE;
                end case;
            end if;
        end if;
    end process;

    result <= result_r;
    flags  <= flags_r;
    done   <= done_r;
    busy   <= busy_r;

end architecture rtl;
