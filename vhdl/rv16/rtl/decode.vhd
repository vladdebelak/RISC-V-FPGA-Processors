-- decode.vhd -- Stage 2: Instruction decode, register file read,
--              immediate generation, control signal generation
-- 16-bit 3-stage RISC-V microcontroller

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decode is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        stall          : in  std_logic;
        flush          : in  std_logic;
        -- From IF/DE pipeline register
        instr          : in  std_logic_vector(31 downto 0);
        ifde_pc        : in  std_logic_vector(15 downto 0);
        ifde_valid     : in  std_logic;
        -- Writeback from execute stage (regfile write port)
        wb_rd          : in  std_logic_vector(3 downto 0);
        wb_data        : in  std_logic_vector(15 downto 0);
        wb_we          : in  std_logic;
        -- DE/EX pipeline register outputs
        deex_rs1_data  : out std_logic_vector(15 downto 0);
        deex_rs2_data  : out std_logic_vector(15 downto 0);
        deex_imm       : out std_logic_vector(15 downto 0);
        deex_pc        : out std_logic_vector(15 downto 0);
        deex_rd        : out std_logic_vector(3 downto 0);
        deex_alu_op    : out std_logic_vector(3 downto 0);
        deex_alu_src   : out std_logic;
        deex_reg_we    : out std_logic;
        deex_mem_we    : out std_logic;
        deex_mem_re    : out std_logic;
        deex_branch_op : out std_logic_vector(1 downto 0);
        deex_wb_sel    : out std_logic_vector(1 downto 0);
        deex_valid     : out std_logic
    );
end entity decode;

architecture rtl of decode is

    -- ALU operations
    constant ALU_ADD    : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB    : std_logic_vector(3 downto 0) := "0001";
    constant ALU_AND    : std_logic_vector(3 downto 0) := "0010";
    constant ALU_OR     : std_logic_vector(3 downto 0) := "0011";
    constant ALU_XOR    : std_logic_vector(3 downto 0) := "0100";
    constant ALU_PASS_B : std_logic_vector(3 downto 0) := "0101";

    -- Immediate types
    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

    -- Branch operations
    constant BR_NONE : std_logic_vector(1 downto 0) := "00";
    constant BR_BEQ  : std_logic_vector(1 downto 0) := "01";
    constant BR_BNE  : std_logic_vector(1 downto 0) := "10";
    constant BR_JAL  : std_logic_vector(1 downto 0) := "11";

    -- Writeback source
    constant WB_ALU : std_logic_vector(1 downto 0) := "00";
    constant WB_MEM : std_logic_vector(1 downto 0) := "01";
    constant WB_PC4 : std_logic_vector(1 downto 0) := "10";

    -- Opcodes
    constant OP_RTYPE : std_logic_vector(6 downto 0) := "0110011";
    constant OP_ADDI  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LW    : std_logic_vector(6 downto 0) := "0000011";
    constant OP_SW    : std_logic_vector(6 downto 0) := "0100011";
    constant OP_LUI   : std_logic_vector(6 downto 0) := "0110111";
    constant OP_JAL   : std_logic_vector(6 downto 0) := "1101111";
    constant OP_BXX   : std_logic_vector(6 downto 0) := "1100011";

    -- Instruction field extraction
    signal opcode   : std_logic_vector(6 downto 0);
    signal funct3   : std_logic_vector(2 downto 0);
    signal funct7_5 : std_logic;
    signal rd_addr  : std_logic_vector(3 downto 0);
    signal rs1_addr : std_logic_vector(3 downto 0);
    signal rs2_addr : std_logic_vector(3 downto 0);

    -- Register file signals
    signal rs1_data : std_logic_vector(15 downto 0);
    signal rs2_data : std_logic_vector(15 downto 0);

    -- Immediate generator signals
    signal imm_type : std_logic_vector(2 downto 0);
    signal imm_out  : std_logic_vector(15 downto 0);

    -- Control signals (combinational)
    signal ctrl_alu_op    : std_logic_vector(3 downto 0);
    signal ctrl_alu_src   : std_logic;
    signal ctrl_reg_we    : std_logic;
    signal ctrl_mem_we    : std_logic;
    signal ctrl_mem_re    : std_logic;
    signal ctrl_branch_op : std_logic_vector(1 downto 0);
    signal ctrl_wb_sel    : std_logic_vector(1 downto 0);

    -- Pipeline register internal signals
    signal deex_rs1_data_r  : std_logic_vector(15 downto 0);
    signal deex_rs2_data_r  : std_logic_vector(15 downto 0);
    signal deex_imm_r       : std_logic_vector(15 downto 0);
    signal deex_pc_r        : std_logic_vector(15 downto 0);
    signal deex_rd_r        : std_logic_vector(3 downto 0);
    signal deex_alu_op_r    : std_logic_vector(3 downto 0);
    signal deex_alu_src_r   : std_logic;
    signal deex_reg_we_r    : std_logic;
    signal deex_mem_we_r    : std_logic;
    signal deex_mem_re_r    : std_logic;
    signal deex_branch_op_r : std_logic_vector(1 downto 0);
    signal deex_wb_sel_r    : std_logic_vector(1 downto 0);
    signal deex_valid_r     : std_logic;

begin

    -- Instruction field extraction
    opcode   <= instr(6 downto 0);
    funct3   <= instr(14 downto 12);
    funct7_5 <= instr(30);
    rd_addr  <= instr(10 downto 7);
    rs1_addr <= instr(18 downto 15);
    rs2_addr <= instr(23 downto 20);

    -- Register file instance
    u_regfile : entity work.regfile
        port map (
            clk      => clk,
            rs1_addr => rs1_addr,
            rs2_addr => rs2_addr,
            rs1_data => rs1_data,
            rs2_data => rs2_data,
            wd_addr  => wb_rd,
            wd_data  => wb_data,
            wd_en    => wb_we
        );

    -- Immediate generator instance
    u_imm_gen : entity work.imm_gen
        port map (
            instr    => instr,
            imm_type => imm_type,
            imm_out  => imm_out
        );

    -- Control decode (combinational)
    process (all)
    begin
        -- Default assignments -- NOP-like
        ctrl_alu_op    <= ALU_ADD;
        ctrl_alu_src   <= '0';
        ctrl_reg_we    <= '0';
        ctrl_mem_we    <= '0';
        ctrl_mem_re    <= '0';
        ctrl_branch_op <= BR_NONE;
        ctrl_wb_sel    <= WB_ALU;
        imm_type       <= IMM_I;

        case opcode is
            when OP_RTYPE =>
                ctrl_alu_src   <= '0';
                ctrl_reg_we    <= '1';
                ctrl_mem_we    <= '0';
                ctrl_mem_re    <= '0';
                ctrl_branch_op <= BR_NONE;
                ctrl_wb_sel    <= WB_ALU;
                case funct3 is
                    when "000"  =>
                        if funct7_5 = '1' then
                            ctrl_alu_op <= ALU_SUB;
                        else
                            ctrl_alu_op <= ALU_ADD;
                        end if;
                    when "111"  => ctrl_alu_op <= ALU_AND;
                    when "110"  => ctrl_alu_op <= ALU_OR;
                    when "100"  => ctrl_alu_op <= ALU_XOR;
                    when others => ctrl_alu_op <= ALU_ADD;
                end case;

            when OP_ADDI =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '1';
                ctrl_branch_op <= BR_NONE;
                ctrl_wb_sel    <= WB_ALU;
                imm_type       <= IMM_I;

            when OP_LW =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '1';
                ctrl_mem_re    <= '1';
                ctrl_branch_op <= BR_NONE;
                ctrl_wb_sel    <= WB_MEM;
                imm_type       <= IMM_I;

            when OP_SW =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '0';
                ctrl_mem_we    <= '1';
                ctrl_branch_op <= BR_NONE;
                imm_type       <= IMM_S;

            when OP_LUI =>
                ctrl_alu_op    <= ALU_PASS_B;
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '1';
                ctrl_branch_op <= BR_NONE;
                ctrl_wb_sel    <= WB_ALU;
                imm_type       <= IMM_U;

            when OP_JAL =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_src   <= '0';
                ctrl_reg_we    <= '1';
                ctrl_branch_op <= BR_JAL;
                ctrl_wb_sel    <= WB_PC4;
                imm_type       <= IMM_J;

            when OP_BXX =>
                ctrl_alu_op    <= ALU_SUB;
                ctrl_alu_src   <= '0';
                ctrl_reg_we    <= '0';
                imm_type       <= IMM_B;
                case funct3 is
                    when "000"  => ctrl_branch_op <= BR_BEQ;
                    when "001"  => ctrl_branch_op <= BR_BNE;
                    when others => ctrl_branch_op <= BR_NONE;
                end case;

            when others =>
                -- All signals stay at default (NOP)
                null;
        end case;
    end process;

    -- DE/EX pipeline register
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                deex_rs1_data_r  <= x"0000";
                deex_rs2_data_r  <= x"0000";
                deex_imm_r       <= x"0000";
                deex_pc_r        <= x"0000";
                deex_rd_r        <= "0000";
                deex_alu_op_r    <= ALU_ADD;
                deex_alu_src_r   <= '0';
                deex_reg_we_r    <= '0';
                deex_mem_we_r    <= '0';
                deex_mem_re_r    <= '0';
                deex_branch_op_r <= BR_NONE;
                deex_wb_sel_r    <= WB_ALU;
                deex_valid_r     <= '0';
            elsif stall = '1' then
                deex_rs1_data_r  <= deex_rs1_data_r;
                deex_rs2_data_r  <= deex_rs2_data_r;
                deex_imm_r       <= deex_imm_r;
                deex_pc_r        <= deex_pc_r;
                deex_rd_r        <= deex_rd_r;
                deex_alu_op_r    <= deex_alu_op_r;
                deex_alu_src_r   <= deex_alu_src_r;
                deex_reg_we_r    <= deex_reg_we_r;
                deex_mem_we_r    <= deex_mem_we_r;
                deex_mem_re_r    <= deex_mem_re_r;
                deex_branch_op_r <= deex_branch_op_r;
                deex_wb_sel_r    <= deex_wb_sel_r;
                deex_valid_r     <= deex_valid_r;
            elsif ifde_valid = '0' then
                -- Insert bubble when incoming instruction is invalid
                deex_rs1_data_r  <= x"0000";
                deex_rs2_data_r  <= x"0000";
                deex_imm_r       <= x"0000";
                deex_pc_r        <= x"0000";
                deex_rd_r        <= "0000";
                deex_alu_op_r    <= ALU_ADD;
                deex_alu_src_r   <= '0';
                deex_reg_we_r    <= '0';
                deex_mem_we_r    <= '0';
                deex_mem_re_r    <= '0';
                deex_branch_op_r <= BR_NONE;
                deex_wb_sel_r    <= WB_ALU;
                deex_valid_r     <= '0';
            else
                deex_rs1_data_r  <= rs1_data;
                deex_rs2_data_r  <= rs2_data;
                deex_imm_r       <= imm_out;
                deex_pc_r        <= ifde_pc;
                deex_rd_r        <= rd_addr;
                deex_alu_op_r    <= ctrl_alu_op;
                deex_alu_src_r   <= ctrl_alu_src;
                deex_reg_we_r    <= ctrl_reg_we;
                deex_mem_we_r    <= ctrl_mem_we;
                deex_mem_re_r    <= ctrl_mem_re;
                deex_branch_op_r <= ctrl_branch_op;
                deex_wb_sel_r    <= ctrl_wb_sel;
                deex_valid_r     <= '1';
            end if;
        end if;
    end process;

    -- Drive outputs from internal registers
    deex_rs1_data  <= deex_rs1_data_r;
    deex_rs2_data  <= deex_rs2_data_r;
    deex_imm       <= deex_imm_r;
    deex_pc        <= deex_pc_r;
    deex_rd        <= deex_rd_r;
    deex_alu_op    <= deex_alu_op_r;
    deex_alu_src   <= deex_alu_src_r;
    deex_reg_we    <= deex_reg_we_r;
    deex_mem_we    <= deex_mem_we_r;
    deex_mem_re    <= deex_mem_re_r;
    deex_branch_op <= deex_branch_op_r;
    deex_wb_sel    <= deex_wb_sel_r;
    deex_valid     <= deex_valid_r;

end architecture rtl;
