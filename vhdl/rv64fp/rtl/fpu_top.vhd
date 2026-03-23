library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fpu_top is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        start         : in  std_logic;
        fp_op         : in  std_logic_vector(4 downto 0);
        rm            : in  std_logic_vector(2 downto 0);
        fp_a          : in  std_logic_vector(63 downto 0);
        fp_b          : in  std_logic_vector(63 downto 0);
        fp_c          : in  std_logic_vector(63 downto 0);
        int_src       : in  std_logic_vector(63 downto 0);
        fp_result     : out std_logic_vector(63 downto 0);
        done          : out std_logic;
        busy          : out std_logic;
        fp_flags      : out std_logic_vector(4 downto 0);
        result_is_int : out std_logic
    );
end entity fpu_top;

architecture rtl of fpu_top is
    -- FP operation codes
    constant FP_ADD     : unsigned(4 downto 0) := "00000";
    constant FP_SUB     : unsigned(4 downto 0) := "00001";
    constant FP_MUL     : unsigned(4 downto 0) := "00010";
    constant FP_DIV     : unsigned(4 downto 0) := "00011";
    constant FP_SQRT    : unsigned(4 downto 0) := "00100";
    constant FP_FMADD   : unsigned(4 downto 0) := "00101";
    constant FP_FMSUB   : unsigned(4 downto 0) := "00110";
    constant FP_FNMSUB  : unsigned(4 downto 0) := "00111";
    constant FP_FNMADD  : unsigned(4 downto 0) := "01000";
    constant FP_SGNJ    : unsigned(4 downto 0) := "01001";
    constant FP_SGNJN   : unsigned(4 downto 0) := "01010";
    constant FP_SGNJX   : unsigned(4 downto 0) := "01011";
    constant FP_MIN     : unsigned(4 downto 0) := "01100";
    constant FP_MAX     : unsigned(4 downto 0) := "01101";
    constant FP_FEQ     : unsigned(4 downto 0) := "01110";
    constant FP_FLT     : unsigned(4 downto 0) := "01111";
    constant FP_FLE     : unsigned(4 downto 0) := "10000";
    constant FP_CVTWD   : unsigned(4 downto 0) := "10001";
    constant FP_CVTWUD  : unsigned(4 downto 0) := "10010";
    constant FP_CVTDW   : unsigned(4 downto 0) := "10011";
    constant FP_CVTDWU  : unsigned(4 downto 0) := "10100";
    constant FP_CVTLD   : unsigned(4 downto 0) := "10101";
    constant FP_CVTLUD  : unsigned(4 downto 0) := "10110";
    constant FP_CVTDL   : unsigned(4 downto 0) := "10111";
    constant FP_CVTDLU  : unsigned(4 downto 0) := "11000";
    constant FP_FCLASS  : unsigned(4 downto 0) := "11001";
    constant FP_MVXD    : unsigned(4 downto 0) := "11010";
    constant FP_MVDX    : unsigned(4 downto 0) := "11011";

    -- Active-unit encoding
    constant UNIT_NONE : unsigned(2 downto 0) := "000";
    constant UNIT_ADD  : unsigned(2 downto 0) := "001";
    constant UNIT_MUL  : unsigned(2 downto 0) := "010";
    constant UNIT_FMA  : unsigned(2 downto 0) := "011";
    constant UNIT_DIV  : unsigned(2 downto 0) := "100";
    constant UNIT_SQRT : unsigned(2 downto 0) := "101";
    constant UNIT_CONV : unsigned(2 downto 0) := "110";

    signal active_unit : unsigned(2 downto 0);
    signal fp_op_u     : unsigned(4 downto 0);

    -- Classification signals
    signal op_is_add, op_is_mul, op_is_fma, op_is_div, op_is_sqrt : std_logic;
    signal op_is_cmp, op_is_conv, op_is_misc, op_is_combinational : std_logic;

    -- Start routing
    signal add_start, mul_start, fma_start, div_start, sqrt_start, conv_start : std_logic;
    signal add_is_sub : std_logic;
    signal fma_op : std_logic_vector(1 downto 0);
    signal cmp_op : std_logic_vector(2 downto 0);
    signal conv_op : std_logic_vector(3 downto 0);
    signal misc_op : std_logic_vector(2 downto 0);

    -- Subunit outputs
    signal add_result, mul_result, fma_result, div_result, sqrt_result : std_logic_vector(63 downto 0);
    signal cmp_result, conv_result, misc_result : std_logic_vector(63 downto 0);
    signal add_done, mul_done, fma_done, div_done, sqrt_done, conv_done : std_logic;
    signal add_busy, mul_busy, fma_busy, div_busy, sqrt_busy, conv_busy : std_logic;
    signal add_flags, mul_flags, fma_flags, div_flags, sqrt_flags : std_logic_vector(4 downto 0);
    signal cmp_flags, conv_flags : std_logic_vector(4 downto 0);
    signal cmp_result_is_int, conv_result_is_int, misc_result_is_int : std_logic;
    signal misc_flags : std_logic_vector(4 downto 0);

    signal comb_active : std_logic;
    signal multicycle_done : std_logic;
    signal result_mux : std_logic_vector(63 downto 0);
    signal flags_mux  : std_logic_vector(4 downto 0);
    signal rint_mux   : std_logic;
    signal done_sig   : std_logic;
begin

    fp_op_u <= unsigned(fp_op);

    -- Operation classification
    op_is_add  <= '1' when fp_op_u = FP_ADD or fp_op_u = FP_SUB else '0';
    op_is_mul  <= '1' when fp_op_u = FP_MUL else '0';
    op_is_fma  <= '1' when fp_op_u = FP_FMADD or fp_op_u = FP_FMSUB or fp_op_u = FP_FNMSUB or fp_op_u = FP_FNMADD else '0';
    op_is_div  <= '1' when fp_op_u = FP_DIV else '0';
    op_is_sqrt <= '1' when fp_op_u = FP_SQRT else '0';
    op_is_cmp  <= '1' when fp_op_u = FP_FEQ or fp_op_u = FP_FLT or fp_op_u = FP_FLE or fp_op_u = FP_MIN or fp_op_u = FP_MAX else '0';
    op_is_conv <= '1' when (fp_op_u >= FP_CVTWD and fp_op_u <= FP_CVTDLU) or fp_op_u = FP_MVXD or fp_op_u = FP_MVDX else '0';
    op_is_misc <= '1' when fp_op_u = FP_SGNJ or fp_op_u = FP_SGNJN or fp_op_u = FP_SGNJX or fp_op_u = FP_FCLASS else '0';
    op_is_combinational <= op_is_cmp or op_is_misc;

    -- Start routing
    add_start  <= start and op_is_add;
    mul_start  <= start and op_is_mul;
    fma_start  <= start and op_is_fma;
    div_start  <= start and op_is_div;
    sqrt_start <= start and op_is_sqrt;
    conv_start <= start and op_is_conv;

    add_is_sub <= '1' when fp_op_u = FP_SUB else '0';

    -- FMA op
    process(all)
    begin
        case fp_op_u is
            when FP_FMADD  => fma_op <= "00";
            when FP_FMSUB  => fma_op <= "01";
            when FP_FNMSUB => fma_op <= "10";
            when FP_FNMADD => fma_op <= "11";
            when others    => fma_op <= "00";
        end case;
    end process;

    -- CMP op
    process(all)
    begin
        case fp_op_u is
            when FP_FEQ  => cmp_op <= "000";
            when FP_FLT  => cmp_op <= "001";
            when FP_FLE  => cmp_op <= "010";
            when FP_MIN  => cmp_op <= "011";
            when FP_MAX  => cmp_op <= "100";
            when others  => cmp_op <= "000";
        end case;
    end process;

    -- CONV op
    process(all)
    begin
        case fp_op_u is
            when FP_CVTWD  => conv_op <= x"0";
            when FP_CVTWUD => conv_op <= x"1";
            when FP_CVTLD  => conv_op <= x"2";
            when FP_CVTLUD => conv_op <= x"3";
            when FP_CVTDW  => conv_op <= x"4";
            when FP_CVTDWU => conv_op <= x"5";
            when FP_CVTDL  => conv_op <= x"6";
            when FP_CVTDLU => conv_op <= x"7";
            when FP_MVXD   => conv_op <= x"8";
            when FP_MVDX   => conv_op <= x"9";
            when others    => conv_op <= x"0";
        end case;
    end process;

    -- MISC op
    process(all)
    begin
        case fp_op_u is
            when FP_SGNJ   => misc_op <= "000";
            when FP_SGNJN  => misc_op <= "001";
            when FP_SGNJX  => misc_op <= "010";
            when FP_FCLASS => misc_op <= "011";
            when others    => misc_op <= "000";
        end case;
    end process;

    misc_flags <= "00000";

    -- Subunit instantiations
    u_fp_add: entity work.fp_add
        port map (clk => clk, rst => rst, start => add_start, rm => rm,
                  is_sub => add_is_sub, a => fp_a, b => fp_b,
                  result => add_result, done => add_done, busy => add_busy, flags => add_flags);

    u_fp_mul: entity work.fp_mul
        port map (clk => clk, rst => rst, start => mul_start, rm => rm,
                  a => fp_a, b => fp_b,
                  result => mul_result, done => mul_done, busy => mul_busy, flags => mul_flags);

    u_fp_fma: entity work.fp_fma
        port map (clk => clk, rst => rst, start => fma_start, rm => rm,
                  op => fma_op, a => fp_a, b => fp_b, c => fp_c,
                  result => fma_result, done => fma_done, busy => fma_busy, flags => fma_flags);

    u_fp_div: entity work.fp_div
        port map (clk => clk, rst => rst, start => div_start, rm => rm,
                  a => fp_a, b => fp_b,
                  result => div_result, done => div_done, busy => div_busy, flags => div_flags);

    u_fp_sqrt: entity work.fp_sqrt
        port map (clk => clk, rst => rst, start => sqrt_start, rm => rm,
                  a => fp_a,
                  result => sqrt_result, done => sqrt_done, busy => sqrt_busy, flags => sqrt_flags);

    u_fp_cmp: entity work.fp_cmp
        port map (op => cmp_op, a => fp_a, b => fp_b,
                  result => cmp_result, flags => cmp_flags, result_is_int => cmp_result_is_int);

    u_fp_conv: entity work.fp_conv
        port map (clk => clk, rst => rst, start => conv_start, rm => rm,
                  op => conv_op, fp_in => fp_a, int_in => int_src,
                  result => conv_result, done => conv_done, busy => conv_busy,
                  flags => conv_flags, result_is_int => conv_result_is_int);

    u_fp_misc: entity work.fp_misc
        port map (op => misc_op, a => fp_a, b => fp_b,
                  result => misc_result, result_is_int => misc_result_is_int);

    -- Active-unit register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                active_unit <= UNIT_NONE;
            elsif start = '1' and op_is_combinational = '0' then
                if op_is_add = '1' then active_unit <= UNIT_ADD;
                elsif op_is_mul = '1' then active_unit <= UNIT_MUL;
                elsif op_is_fma = '1' then active_unit <= UNIT_FMA;
                elsif op_is_div = '1' then active_unit <= UNIT_DIV;
                elsif op_is_sqrt = '1' then active_unit <= UNIT_SQRT;
                elsif op_is_conv = '1' then active_unit <= UNIT_CONV;
                else active_unit <= UNIT_NONE;
                end if;
            elsif done_sig = '1' then
                active_unit <= UNIT_NONE;
            end if;
        end if;
    end process;

    comb_active <= start and op_is_combinational;
    busy <= add_busy or mul_busy or fma_busy or div_busy or sqrt_busy or conv_busy;

    -- Multicycle done
    process(all)
    begin
        multicycle_done <= '0';
        case active_unit is
            when UNIT_ADD  => multicycle_done <= add_done;
            when UNIT_MUL  => multicycle_done <= mul_done;
            when UNIT_FMA  => multicycle_done <= fma_done;
            when UNIT_DIV  => multicycle_done <= div_done;
            when UNIT_SQRT => multicycle_done <= sqrt_done;
            when UNIT_CONV => multicycle_done <= conv_done;
            when others    => multicycle_done <= '0';
        end case;
    end process;

    done_sig <= comb_active or multicycle_done;
    done <= done_sig;

    -- Result mux
    process(all)
    begin
        result_mux <= (others => '0');
        flags_mux  <= (others => '0');
        rint_mux   <= '0';
        if comb_active = '1' then
            if op_is_cmp = '1' then
                result_mux <= cmp_result; flags_mux <= cmp_flags; rint_mux <= cmp_result_is_int;
            elsif op_is_misc = '1' then
                result_mux <= misc_result; flags_mux <= misc_flags; rint_mux <= misc_result_is_int;
            end if;
        else
            case active_unit is
                when UNIT_ADD  => result_mux <= add_result; flags_mux <= add_flags;
                when UNIT_MUL  => result_mux <= mul_result; flags_mux <= mul_flags;
                when UNIT_FMA  => result_mux <= fma_result; flags_mux <= fma_flags;
                when UNIT_DIV  => result_mux <= div_result; flags_mux <= div_flags;
                when UNIT_SQRT => result_mux <= sqrt_result; flags_mux <= sqrt_flags;
                when UNIT_CONV => result_mux <= conv_result; flags_mux <= conv_flags; rint_mux <= conv_result_is_int;
                when others    => null;
            end case;
        end if;
    end process;

    fp_result     <= result_mux;
    fp_flags      <= flags_mux;
    result_is_int <= rint_mux;

end architecture rtl;
