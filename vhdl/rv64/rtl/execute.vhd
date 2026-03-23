-- execute.vhd — EX stage for 3-stage RV64I pipeline
-- ALU, branch resolution, JALR, memory interface, writeback mux

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity execute is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        -- DE/EX pipeline inputs
        deex_rs1_data    : in  std_logic_vector(63 downto 0);
        deex_rs2_data    : in  std_logic_vector(63 downto 0);
        deex_imm         : in  std_logic_vector(63 downto 0);
        deex_pc          : in  std_logic_vector(63 downto 0);
        deex_rd          : in  std_logic_vector(4 downto 0);
        deex_alu_op      : in  std_logic_vector(4 downto 0);
        deex_alu_src     : in  std_logic;
        deex_alu_a_sel   : in  std_logic;
        deex_reg_we      : in  std_logic;
        deex_mem_we      : in  std_logic;
        deex_mem_re      : in  std_logic;
        deex_branch_op   : in  std_logic_vector(3 downto 0);
        deex_wb_sel      : in  std_logic_vector(1 downto 0);
        deex_mem_size    : in  std_logic_vector(1 downto 0);
        deex_mem_unsigned : in  std_logic;
        deex_valid       : in  std_logic;
        -- Memory interface
        mem_addr         : out std_logic_vector(63 downto 0);
        mem_wdata        : out std_logic_vector(63 downto 0);
        mem_rdata        : in  std_logic_vector(63 downto 0);
        mem_we           : out std_logic;
        mem_re           : out std_logic;
        mem_size         : out std_logic_vector(1 downto 0);
        mem_unsigned     : out std_logic;
        -- Branch feedback to fetch
        branch_taken     : out std_logic;
        branch_target    : out std_logic_vector(63 downto 0);
        jalr_taken       : out std_logic;
        jalr_target      : out std_logic_vector(63 downto 0);
        -- Writeback to decode
        wb_rd            : out std_logic_vector(4 downto 0);
        wb_data          : out std_logic_vector(63 downto 0);
        wb_we            : out std_logic
    );
end entity execute;

architecture rtl of execute is

    -- ALU ops (5-bit)
    constant ALU_ADD    : std_logic_vector(4 downto 0) := "00000";
    constant ALU_SUB    : std_logic_vector(4 downto 0) := "00001";
    constant ALU_AND    : std_logic_vector(4 downto 0) := "00010";
    constant ALU_OR     : std_logic_vector(4 downto 0) := "00011";
    constant ALU_XOR    : std_logic_vector(4 downto 0) := "00100";
    constant ALU_SLL    : std_logic_vector(4 downto 0) := "00101";
    constant ALU_SRL    : std_logic_vector(4 downto 0) := "00110";
    constant ALU_SRA    : std_logic_vector(4 downto 0) := "00111";
    constant ALU_SLT    : std_logic_vector(4 downto 0) := "01000";
    constant ALU_SLTU   : std_logic_vector(4 downto 0) := "01001";
    constant ALU_PASS_B : std_logic_vector(4 downto 0) := "01010";
    constant ALU_ADDW   : std_logic_vector(4 downto 0) := "10000";
    constant ALU_SUBW   : std_logic_vector(4 downto 0) := "10001";
    constant ALU_SLLW   : std_logic_vector(4 downto 0) := "10101";
    constant ALU_SRLW   : std_logic_vector(4 downto 0) := "10110";
    constant ALU_SRAW   : std_logic_vector(4 downto 0) := "10111";

    -- Branch ops (4-bit)
    constant BR_NONE : std_logic_vector(3 downto 0) := "0000";
    constant BR_BEQ  : std_logic_vector(3 downto 0) := "0001";
    constant BR_BNE  : std_logic_vector(3 downto 0) := "0010";
    constant BR_JAL  : std_logic_vector(3 downto 0) := "0011";
    constant BR_JALR : std_logic_vector(3 downto 0) := "0100";
    constant BR_BLT  : std_logic_vector(3 downto 0) := "0101";
    constant BR_BGE  : std_logic_vector(3 downto 0) := "0110";
    constant BR_BLTU : std_logic_vector(3 downto 0) := "0111";
    constant BR_BGEU : std_logic_vector(3 downto 0) := "1000";

    -- WB select (2-bit)
    constant WB_ALU : std_logic_vector(1 downto 0) := "00";
    constant WB_MEM : std_logic_vector(1 downto 0) := "01";
    constant WB_PC4 : std_logic_vector(1 downto 0) := "10";

    -- ALU input muxes
    signal alu_a : std_logic_vector(63 downto 0);
    signal alu_b : std_logic_vector(63 downto 0);

    -- ALU
    signal alu_result : std_logic_vector(63 downto 0);
    signal alu_a_w    : std_logic_vector(31 downto 0);
    signal alu_b_w    : std_logic_vector(31 downto 0);
    signal result_w   : std_logic_vector(31 downto 0);

    -- Branch comparison flags
    signal alu_zero        : std_logic;
    signal alu_lt_signed   : std_logic;
    signal alu_lt_unsigned : std_logic;

    -- Branch / JALR resolution
    signal br_taken_r   : std_logic;
    signal jalr_taken_r : std_logic;

    -- Writeback
    signal wb_data_r : std_logic_vector(63 downto 0);

begin

    -- ALU input muxes
    alu_a <= deex_pc       when deex_alu_a_sel = '1' else deex_rs1_data;
    alu_b <= deex_imm      when deex_alu_src = '1'   else deex_rs2_data;

    alu_a_w <= alu_a(31 downto 0);
    alu_b_w <= alu_b(31 downto 0);

    -- ALU (combinational)
    process (all)
        variable shamt   : natural;
        variable shamt_w : natural;
        variable tmp_w   : signed(31 downto 0);
    begin
        alu_result <= (others => '0');
        result_w   <= (others => '0');

        case deex_alu_op is
            when ALU_ADD =>
                alu_result <= std_logic_vector(unsigned(alu_a) + unsigned(alu_b));
            when ALU_SUB =>
                alu_result <= std_logic_vector(unsigned(alu_a) - unsigned(alu_b));
            when ALU_AND =>
                alu_result <= alu_a and alu_b;
            when ALU_OR =>
                alu_result <= alu_a or alu_b;
            when ALU_XOR =>
                alu_result <= alu_a xor alu_b;
            when ALU_SLL =>
                shamt := to_integer(unsigned(alu_b(5 downto 0)));
                alu_result <= std_logic_vector(shift_left(unsigned(alu_a), shamt));
            when ALU_SRL =>
                shamt := to_integer(unsigned(alu_b(5 downto 0)));
                alu_result <= std_logic_vector(shift_right(unsigned(alu_a), shamt));
            when ALU_SRA =>
                shamt := to_integer(unsigned(alu_b(5 downto 0)));
                alu_result <= std_logic_vector(shift_right(signed(alu_a), shamt));
            when ALU_SLT =>
                if signed(alu_a) < signed(alu_b) then
                    alu_result <= (0 => '1', others => '0');
                else
                    alu_result <= (others => '0');
                end if;
            when ALU_SLTU =>
                if unsigned(alu_a) < unsigned(alu_b) then
                    alu_result <= (0 => '1', others => '0');
                else
                    alu_result <= (others => '0');
                end if;
            when ALU_PASS_B =>
                alu_result <= alu_b;
            when ALU_ADDW =>
                result_w   <= std_logic_vector(unsigned(alu_a_w) + unsigned(alu_b_w));
                alu_result <= (63 downto 32 => result_w(31)) & result_w;
            when ALU_SUBW =>
                result_w   <= std_logic_vector(unsigned(alu_a_w) - unsigned(alu_b_w));
                alu_result <= (63 downto 32 => result_w(31)) & result_w;
            when ALU_SLLW =>
                shamt_w  := to_integer(unsigned(alu_b(4 downto 0)));
                result_w <= std_logic_vector(shift_left(unsigned(alu_a_w), shamt_w));
                alu_result <= (63 downto 32 => result_w(31)) & result_w;
            when ALU_SRLW =>
                shamt_w  := to_integer(unsigned(alu_b(4 downto 0)));
                result_w <= std_logic_vector(shift_right(unsigned(alu_a_w), shamt_w));
                alu_result <= (63 downto 32 => result_w(31)) & result_w;
            when ALU_SRAW =>
                shamt_w  := to_integer(unsigned(alu_b(4 downto 0)));
                tmp_w    := shift_right(signed(alu_a_w), shamt_w);
                result_w <= std_logic_vector(tmp_w);
                alu_result <= (63 downto 32 => result_w(31)) & result_w;
            when others =>
                alu_result <= (others => '0');
        end case;
    end process;

    -- Branch comparison flags
    alu_zero        <= '1' when deex_rs1_data = deex_rs2_data else '0';
    alu_lt_signed   <= '1' when signed(deex_rs1_data) < signed(deex_rs2_data) else '0';
    alu_lt_unsigned <= '1' when unsigned(deex_rs1_data) < unsigned(deex_rs2_data) else '0';

    -- Branch / JALR resolution
    branch_target <= std_logic_vector(unsigned(deex_pc) + unsigned(deex_imm));
    jalr_target   <= std_logic_vector(unsigned(deex_rs1_data) + unsigned(deex_imm)) and
                     (63 downto 1 => '1') & '0';  -- clear bit 0

    process (all)
    begin
        br_taken_r   <= '0';
        jalr_taken_r <= '0';
        if deex_valid = '1' then
            case deex_branch_op is
                when BR_JAL  => br_taken_r   <= '1';
                when BR_JALR => jalr_taken_r <= '1';
                when BR_BEQ  => br_taken_r   <= alu_zero;
                when BR_BNE  => br_taken_r   <= not alu_zero;
                when BR_BLT  => br_taken_r   <= alu_lt_signed;
                when BR_BGE  => br_taken_r   <= not alu_lt_signed;
                when BR_BLTU => br_taken_r   <= alu_lt_unsigned;
                when BR_BGEU => br_taken_r   <= not alu_lt_unsigned;
                when others =>
                    br_taken_r   <= '0';
                    jalr_taken_r <= '0';
            end case;
        end if;
    end process;

    branch_taken <= br_taken_r;
    jalr_taken   <= jalr_taken_r;

    -- Memory interface
    mem_addr     <= alu_result;
    mem_wdata    <= deex_rs2_data;
    mem_we       <= deex_mem_we and deex_valid;
    mem_re       <= deex_mem_re and deex_valid;
    mem_size     <= deex_mem_size;
    mem_unsigned <= deex_mem_unsigned;

    -- Writeback mux
    process (all)
    begin
        wb_data_r <= (others => '0');
        case deex_wb_sel is
            when WB_ALU => wb_data_r <= alu_result;
            when WB_MEM => wb_data_r <= mem_rdata;
            when WB_PC4 => wb_data_r <= std_logic_vector(unsigned(deex_pc) + to_unsigned(4, 64));
            when others => wb_data_r <= (others => '0');
        end case;
    end process;

    wb_data <= wb_data_r;
    wb_rd   <= deex_rd;
    wb_we   <= deex_reg_we and deex_valid;

end architecture rtl;
