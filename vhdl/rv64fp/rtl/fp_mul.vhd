library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_mul is
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
end entity fp_mul;

architecture rtl of fp_mul is
    type state_type is (IDLE, STAGE1, STAGE2, STAGE3);
    signal state : state_type;

    constant EXP_INF   : unsigned(10 downto 0) := "11111111111";
    constant BIAS      : unsigned(10 downto 0) := to_unsigned(1023, 11);
    constant CANON_NAN : std_logic_vector(63 downto 0) := x"7FF8000000000000";

    signal a_sign, b_sign, res_sign : std_logic;
    signal a_exp, b_exp             : unsigned(10 downto 0);
    signal a_mant, b_mant           : unsigned(52 downto 0);
    signal a_is_zero, b_is_zero     : std_logic;
    signal a_is_inf, b_is_inf       : std_logic;
    signal a_is_nan, b_is_nan       : std_logic;
    signal a_is_snan, b_is_snan     : std_logic;
    signal a_is_sub, b_is_sub       : std_logic;
    signal special_case_r           : std_logic;
    signal special_result_r         : std_logic_vector(63 downto 0);
    signal special_flags_r          : std_logic_vector(4 downto 0);
    signal res_exp_s                : signed(12 downto 0);
    signal product_r                : unsigned(105 downto 0);

    signal rnd_sign_s, rnd_guard_s, rnd_round_s, rnd_sticky_s, rnd_lsb_s : std_logic;
    signal round_up_s : std_logic;

    signal result_r : std_logic_vector(63 downto 0);
    signal flags_r  : std_logic_vector(4 downto 0);
    signal done_r   : std_logic;
    signal busy_r   : std_logic;
begin

    u_round: entity work.fp_round
        port map (
            sign => rnd_sign_s, guard => rnd_guard_s, round_bit => rnd_round_s,
            sticky => rnd_sticky_s, lsb => rnd_lsb_s, rm => rm, round_up => round_up_s
        );

    process(clk)
        variable norm_exp    : signed(12 downto 0);
        variable s3_guard, s3_round, s3_sticky : std_logic;
        variable final_mant  : unsigned(51 downto 0);
        variable final_exp   : unsigned(10 downto 0);
        variable final_flags : std_logic_vector(4 downto 0);
        variable shift_right_v : signed(12 downto 0);
        variable mant_full   : unsigned(52 downto 0);
        variable shifted_mant: unsigned(52 downto 0);
        variable uf_sticky   : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                result_r <= (others => '0');
                flags_r <= (others => '0');
                done_r <= '0';
                busy_r <= '0';
                a_sign <= '0'; b_sign <= '0'; res_sign <= '0';
                a_exp <= (others => '0'); b_exp <= (others => '0');
                a_mant <= (others => '0'); b_mant <= (others => '0');
                a_is_zero <= '0'; b_is_zero <= '0';
                a_is_inf <= '0'; b_is_inf <= '0';
                a_is_nan <= '0'; b_is_nan <= '0';
                a_is_snan <= '0'; b_is_snan <= '0';
                a_is_sub <= '0'; b_is_sub <= '0';
                special_case_r <= '0'; special_result_r <= (others => '0'); special_flags_r <= (others => '0');
                res_exp_s <= (others => '0');
                product_r <= (others => '0');
            else
                done_r <= '0';
                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= STAGE1;
                            busy_r <= '1';
                            flags_r <= (others => '0');
                            a_sign <= a(63); b_sign <= b(63);
                            a_exp <= unsigned(a(62 downto 52)); b_exp <= unsigned(b(62 downto 52));
                            if unsigned(a(62 downto 52)) = 0 then a_mant <= unsigned('0' & a(51 downto 0));
                            else a_mant <= unsigned('1' & a(51 downto 0)); end if;
                            if unsigned(b(62 downto 52)) = 0 then b_mant <= unsigned('0' & b(51 downto 0));
                            else b_mant <= unsigned('1' & b(51 downto 0)); end if;
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
                            res_sign <= a(63) xor b(63);
                        end if;

                    when STAGE1 =>
                        if a_is_nan = '1' or b_is_nan = '1' then
                            special_case_r <= '1'; special_result_r <= CANON_NAN;
                            special_flags_r <= (4 => (a_is_snan or b_is_snan), others => '0');
                        elsif (a_is_inf = '1' and b_is_zero = '1') or (a_is_zero = '1' and b_is_inf = '1') then
                            special_case_r <= '1'; special_result_r <= CANON_NAN; special_flags_r <= "10000";
                        elsif a_is_inf = '1' or b_is_inf = '1' then
                            special_case_r <= '1';
                            special_result_r <= res_sign & std_logic_vector(EXP_INF) & (51 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        elsif a_is_zero = '1' or b_is_zero = '1' then
                            special_case_r <= '1';
                            special_result_r <= res_sign & (62 downto 0 => '0');
                            special_flags_r <= (others => '0');
                        else
                            special_case_r <= '0';
                        end if;
                        -- Compute exponent
                        if a_is_sub = '0' and b_is_sub = '0' then
                            res_exp_s <= signed("00" & a_exp) + signed("00" & b_exp) - signed("00" & BIAS);
                        elsif a_is_sub = '1' and b_is_sub = '0' then
                            res_exp_s <= to_signed(1, 13) + signed("00" & b_exp) - signed("00" & BIAS);
                        elsif a_is_sub = '0' and b_is_sub = '1' then
                            res_exp_s <= signed("00" & a_exp) + to_signed(1, 13) - signed("00" & BIAS);
                        else
                            res_exp_s <= to_signed(1, 13) + to_signed(1, 13) - signed("00" & BIAS);
                        end if;
                        state <= STAGE2;

                    when STAGE2 =>
                        if special_case_r = '1' then
                            result_r <= special_result_r;
                            flags_r <= special_flags_r;
                            done_r <= '1'; busy_r <= '0'; state <= IDLE;
                        else
                            product_r <= a_mant * b_mant;
                            state <= STAGE3;
                        end if;

                    when STAGE3 =>
                        final_flags := (others => '0');
                        if product_r(105) = '1' then
                            norm_exp  := res_exp_s + 1;
                            s3_guard  := product_r(52);
                            s3_round  := product_r(51);
                            s3_sticky := '1' when product_r(50 downto 0) /= 0 else '0';
                            final_mant := product_r(104 downto 53);
                        else
                            norm_exp  := res_exp_s;
                            s3_guard  := product_r(51);
                            s3_round  := product_r(50);
                            s3_sticky := '1' when product_r(49 downto 0) /= 0 else '0';
                            final_mant := product_r(103 downto 52);
                        end if;
                        -- Rounding
                        rnd_sign_s <= res_sign; rnd_guard_s <= s3_guard;
                        rnd_round_s <= s3_round; rnd_sticky_s <= s3_sticky;
                        rnd_lsb_s <= final_mant(0);
                        if round_up_s = '1' then
                            final_mant := final_mant + 1;
                            if final_mant = 0 then norm_exp := norm_exp + 1; end if;
                        end if;
                        -- Overflow
                        if norm_exp >= 2047 then
                            final_flags := final_flags or "00101";
                            case rm is
                                when "000" | "100" => final_exp := EXP_INF; final_mant := (others => '0');
                                when "001" => final_exp := "11111111110"; final_mant := (others => '1');
                                when "010" =>
                                    if res_sign = '1' then final_exp := EXP_INF; final_mant := (others => '0');
                                    else final_exp := "11111111110"; final_mant := (others => '1'); end if;
                                when "011" =>
                                    if res_sign = '1' then final_exp := "11111111110"; final_mant := (others => '1');
                                    else final_exp := EXP_INF; final_mant := (others => '0'); end if;
                                when others => final_exp := EXP_INF; final_mant := (others => '0');
                            end case;
                        elsif norm_exp <= 0 then
                            -- Underflow
                            shift_right_v := 1 - norm_exp;
                            if shift_right_v >= 53 then
                                final_exp := (others => '0'); final_mant := (others => '0');
                                uf_sticky := '1' when product_r /= 0 else '0';
                            else
                                if product_r(105) = '1' then mant_full := product_r(105 downto 53);
                                else mant_full := product_r(104 downto 52); end if;
                                shifted_mant := shift_right(mant_full, to_integer(shift_right_v));
                                final_mant := shifted_mant(51 downto 0);
                                uf_sticky := s3_guard or s3_round or s3_sticky;
                                for i in 0 to 52 loop
                                    if i < to_integer(shift_right_v) then
                                        uf_sticky := uf_sticky or mant_full(i);
                                    end if;
                                end loop;
                                final_exp := (others => '0');
                            end if;
                            if uf_sticky = '1' or s3_guard = '1' or s3_round = '1' or s3_sticky = '1' then
                                final_flags := final_flags or "00011";
                            end if;
                        else
                            final_exp := unsigned(norm_exp(10 downto 0));
                            if s3_guard = '1' or s3_round = '1' or s3_sticky = '1' then
                                final_flags := final_flags or "00001";
                            end if;
                        end if;
                        result_r <= res_sign & std_logic_vector(final_exp) & std_logic_vector(final_mant);
                        flags_r <= final_flags;
                        done_r <= '1'; busy_r <= '0'; state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    result <= result_r; flags <= flags_r; done <= done_r; busy <= busy_r;
end architecture rtl;
