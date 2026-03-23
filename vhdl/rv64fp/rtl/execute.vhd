library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity execute is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        stall_ex         : in  std_logic;
        flush_ex         : in  std_logic;
        idex_rs1_data    : in  std_logic_vector(63 downto 0);
        idex_rs2_data    : in  std_logic_vector(63 downto 0);
        idex_imm         : in  std_logic_vector(63 downto 0);
        idex_pc          : in  std_logic_vector(63 downto 0);
        idex_fp_rs1_data : in  std_logic_vector(63 downto 0);
        idex_fp_rs2_data : in  std_logic_vector(63 downto 0);
        idex_fp_rs3_data : in  std_logic_vector(63 downto 0);
        idex_rd          : in  std_logic_vector(4 downto 0);
        idex_alu_op      : in  std_logic_vector(4 downto 0);
        idex_alu_src     : in  std_logic;
        idex_alu_a_sel   : in  std_logic;
        idex_reg_we      : in  std_logic;
        idex_fp_reg_we   : in  std_logic;
        idex_mem_we      : in  std_logic;
        idex_mem_re      : in  std_logic;
        idex_branch_op   : in  std_logic_vector(3 downto 0);
        idex_wb_sel      : in  std_logic_vector(2 downto 0);
        idex_mem_size    : in  std_logic_vector(1 downto 0);
        idex_mem_unsigned: in  std_logic;
        idex_valid       : in  std_logic;
        idex_fp_en       : in  std_logic;
        idex_fp_op       : in  std_logic_vector(4 downto 0);
        idex_fp_rm       : in  std_logic_vector(2 downto 0);
        idex_is_fp_load  : in  std_logic;
        idex_is_fp_store : in  std_logic;
        branch_taken     : out std_logic;
        branch_target    : out std_logic_vector(63 downto 0);
        jalr_taken       : out std_logic;
        jalr_target      : out std_logic_vector(63 downto 0);
        fpu_busy         : out std_logic;
        fpu_flags_out    : out std_logic_vector(4 downto 0);
        fpu_done         : out std_logic;
        -- Combinational EX result (for forwarding to decode before latch)
        ex_result_comb   : out std_logic_vector(63 downto 0);
        ex_fp_result_comb: out std_logic_vector(63 downto 0);
        exmem_alu_result : out std_logic_vector(63 downto 0);
        exmem_rs2_data   : out std_logic_vector(63 downto 0);
        exmem_rd         : out std_logic_vector(4 downto 0);
        exmem_reg_we     : out std_logic;
        exmem_fp_reg_we  : out std_logic;
        exmem_mem_we     : out std_logic;
        exmem_mem_re     : out std_logic;
        exmem_wb_sel     : out std_logic_vector(2 downto 0);
        exmem_mem_size   : out std_logic_vector(1 downto 0);
        exmem_mem_unsigned : out std_logic;
        exmem_valid      : out std_logic;
        exmem_is_fp_load : out std_logic;
        exmem_is_fp_store: out std_logic
    );
end entity execute;

architecture rtl of execute is
    constant BR_NONE : std_logic_vector(3 downto 0) := x"0";
    constant BR_BEQ  : std_logic_vector(3 downto 0) := x"1";
    constant BR_BNE  : std_logic_vector(3 downto 0) := x"2";
    constant BR_JAL  : std_logic_vector(3 downto 0) := x"3";
    constant BR_JALR : std_logic_vector(3 downto 0) := x"4";
    constant BR_BLT  : std_logic_vector(3 downto 0) := x"5";
    constant BR_BGE  : std_logic_vector(3 downto 0) := x"6";
    constant BR_BLTU : std_logic_vector(3 downto 0) := x"7";
    constant BR_BGEU : std_logic_vector(3 downto 0) := x"8";

    signal alu_a, alu_b : std_logic_vector(63 downto 0);
    signal alu_result   : std_logic_vector(63 downto 0);
    signal zero_sig     : std_logic;
    signal lt_signed_sig: std_logic;
    signal lt_unsigned_sig : std_logic;
    signal br_take      : std_logic;
    signal pc_plus_4    : std_logic_vector(63 downto 0);
    signal fpu_result   : std_logic_vector(63 downto 0);
    signal fpu_done_w   : std_logic;
    signal fpu_busy_w   : std_logic;
    signal fpu_flags_w  : std_logic_vector(4 downto 0);
    signal fpu_result_is_int : std_logic;
    signal ex_result    : std_logic_vector(63 downto 0);
    signal store_data   : std_logic_vector(63 downto 0);

    -- Internal signals for output ports
    signal exmem_alu_result_r : std_logic_vector(63 downto 0);
    signal exmem_rs2_data_r   : std_logic_vector(63 downto 0);
    signal exmem_rd_r         : std_logic_vector(4 downto 0);
    signal exmem_reg_we_r     : std_logic;
    signal exmem_fp_reg_we_r  : std_logic;
    signal exmem_mem_we_r     : std_logic;
    signal exmem_mem_re_r     : std_logic;
    signal exmem_wb_sel_r     : std_logic_vector(2 downto 0);
    signal exmem_mem_size_r   : std_logic_vector(1 downto 0);
    signal exmem_mem_unsigned_r : std_logic;
    signal exmem_valid_r      : std_logic;
    signal exmem_is_fp_load_r : std_logic;
    signal exmem_is_fp_store_r: std_logic;
begin

    alu_a <= idex_pc when idex_alu_a_sel = '1' else idex_rs1_data;
    alu_b <= idex_imm when idex_alu_src = '1' else idex_rs2_data;

    u_alu: entity work.alu
        port map (
            a      => alu_a,
            b      => alu_b,
            alu_op => idex_alu_op,
            result => alu_result,
            zero   => open,
            lt_signed   => open,
            lt_unsigned => open
        );

    -- Branch comparison (using rs1_data and rs2_data directly)
    zero_sig       <= '1' when idex_rs1_data = idex_rs2_data else '0';
    lt_signed_sig  <= '1' when signed(idex_rs1_data) < signed(idex_rs2_data) else '0';
    lt_unsigned_sig <= '1' when unsigned(idex_rs1_data) < unsigned(idex_rs2_data) else '0';

    -- Branch resolution
    process(all)
    begin
        br_take <= '0';
        case idex_branch_op is
            when BR_NONE => br_take <= '0';
            when BR_BEQ  => br_take <= zero_sig;
            when BR_BNE  => br_take <= not zero_sig;
            when BR_JAL  => br_take <= '1';
            when BR_JALR => br_take <= '0';
            when BR_BLT  => br_take <= lt_signed_sig;
            when BR_BGE  => br_take <= not lt_signed_sig;
            when BR_BLTU => br_take <= lt_unsigned_sig;
            when BR_BGEU => br_take <= not lt_unsigned_sig;
            when others  => br_take <= '0';
        end case;
    end process;

    branch_taken  <= br_take and idex_valid;
    branch_target <= std_logic_vector(unsigned(idex_pc) + unsigned(idex_imm));
    jalr_taken    <= '1' when idex_branch_op = BR_JALR and idex_valid = '1' else '0';
    jalr_target   <= std_logic_vector(unsigned(idex_rs1_data) + unsigned(idex_imm)) and (63 downto 1 => '1') & '0';

    pc_plus_4 <= std_logic_vector(unsigned(idex_pc) + 4);

    ex_result <= fpu_result when idex_fp_en = '1' else
                 pc_plus_4 when (idex_branch_op = BR_JAL or idex_branch_op = BR_JALR) else
                 alu_result;

    -- Combinational forwarding outputs (available before EX/MEM latch)
    ex_result_comb    <= ex_result;
    ex_fp_result_comb <= fpu_result;

    -- FPU Instance
    u_fpu: entity work.fpu_top
        port map (
            clk           => clk,
            rst           => rst,
            start         => idex_fp_en and idex_valid and (not stall_ex),
            fp_op         => idex_fp_op,
            rm            => idex_fp_rm,
            fp_a          => idex_fp_rs1_data,
            fp_b          => idex_fp_rs2_data,
            fp_c          => idex_fp_rs3_data,
            int_src       => idex_rs1_data,
            fp_result     => fpu_result,
            done          => fpu_done_w,
            busy          => fpu_busy_w,
            fp_flags      => fpu_flags_w,
            result_is_int => fpu_result_is_int
        );

    fpu_busy      <= fpu_busy_w;
    fpu_flags_out <= fpu_flags_w;
    fpu_done      <= fpu_done_w;

    store_data <= idex_fp_rs2_data when idex_is_fp_store = '1' else idex_rs2_data;

    -- EX/MEM Pipeline Register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_ex = '1' then
                exmem_alu_result_r   <= (others => '0');
                exmem_rs2_data_r     <= (others => '0');
                exmem_rd_r           <= (others => '0');
                exmem_reg_we_r       <= '0';
                exmem_fp_reg_we_r    <= '0';
                exmem_mem_we_r       <= '0';
                exmem_mem_re_r       <= '0';
                exmem_wb_sel_r       <= (others => '0');
                exmem_mem_size_r     <= (others => '0');
                exmem_mem_unsigned_r <= '0';
                exmem_valid_r        <= '0';
                exmem_is_fp_load_r   <= '0';
                exmem_is_fp_store_r  <= '0';
            elsif stall_ex = '0' then
                exmem_alu_result_r   <= ex_result;
                exmem_rs2_data_r     <= store_data;
                exmem_rd_r           <= idex_rd;
                exmem_reg_we_r       <= idex_reg_we;
                exmem_fp_reg_we_r    <= idex_fp_reg_we;
                exmem_mem_we_r       <= idex_mem_we;
                exmem_mem_re_r       <= idex_mem_re;
                exmem_wb_sel_r       <= idex_wb_sel;
                exmem_mem_size_r     <= idex_mem_size;
                exmem_mem_unsigned_r <= idex_mem_unsigned;
                exmem_valid_r        <= idex_valid;
                exmem_is_fp_load_r   <= idex_is_fp_load;
                exmem_is_fp_store_r  <= idex_is_fp_store;
            end if;
        end if;
    end process;

    exmem_alu_result   <= exmem_alu_result_r;
    exmem_rs2_data     <= exmem_rs2_data_r;
    exmem_rd           <= exmem_rd_r;
    exmem_reg_we       <= exmem_reg_we_r;
    exmem_fp_reg_we    <= exmem_fp_reg_we_r;
    exmem_mem_we       <= exmem_mem_we_r;
    exmem_mem_re       <= exmem_mem_re_r;
    exmem_wb_sel       <= exmem_wb_sel_r;
    exmem_mem_size     <= exmem_mem_size_r;
    exmem_mem_unsigned <= exmem_mem_unsigned_r;
    exmem_valid        <= exmem_valid_r;
    exmem_is_fp_load   <= exmem_is_fp_load_r;
    exmem_is_fp_store  <= exmem_is_fp_store_r;

end architecture rtl;
