library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decode is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        stall_id         : in  std_logic;
        flush_id         : in  std_logic;
        instr            : in  std_logic_vector(31 downto 0);
        ifid_pc          : in  std_logic_vector(63 downto 0);
        ifid_valid       : in  std_logic;
        fcsr_frm         : in  std_logic_vector(2 downto 0);
        wb_rd            : in  std_logic_vector(4 downto 0);
        wb_data          : in  std_logic_vector(63 downto 0);
        wb_reg_we        : in  std_logic;
        wb_fp_reg_we     : in  std_logic;
        wb_fp_data       : in  std_logic_vector(63 downto 0);
        fwd_rs1_sel      : in  std_logic_vector(1 downto 0);
        fwd_rs2_sel      : in  std_logic_vector(1 downto 0);
        fwd_fp_rs1_sel   : in  std_logic_vector(1 downto 0);
        fwd_fp_rs2_sel   : in  std_logic_vector(1 downto 0);
        fwd_fp_rs3_sel   : in  std_logic_vector(1 downto 0);
        -- Forwarded data from EX (combinational), EX/MEM, and MEM/WB
        ex_result        : in  std_logic_vector(63 downto 0);
        exmem_result     : in  std_logic_vector(63 downto 0);
        memwb_result     : in  std_logic_vector(63 downto 0);
        ex_fp_result     : in  std_logic_vector(63 downto 0);
        exmem_fp_result  : in  std_logic_vector(63 downto 0);
        memwb_fp_result  : in  std_logic_vector(63 downto 0);
        id_rs1_addr      : out std_logic_vector(4 downto 0);
        id_rs2_addr      : out std_logic_vector(4 downto 0);
        id_rs1_used      : out std_logic;
        id_rs2_used      : out std_logic;
        id_fp_rs1_addr   : out std_logic_vector(4 downto 0);
        id_fp_rs2_addr   : out std_logic_vector(4 downto 0);
        id_fp_rs3_addr   : out std_logic_vector(4 downto 0);
        id_fp_rs1_used   : out std_logic;
        id_fp_rs2_used   : out std_logic;
        id_fp_rs3_used   : out std_logic;
        idex_rs1_data    : out std_logic_vector(63 downto 0);
        idex_rs2_data    : out std_logic_vector(63 downto 0);
        idex_imm         : out std_logic_vector(63 downto 0);
        idex_pc          : out std_logic_vector(63 downto 0);
        idex_fp_rs1_data : out std_logic_vector(63 downto 0);
        idex_fp_rs2_data : out std_logic_vector(63 downto 0);
        idex_fp_rs3_data : out std_logic_vector(63 downto 0);
        idex_rd          : out std_logic_vector(4 downto 0);
        idex_alu_op      : out std_logic_vector(4 downto 0);
        idex_alu_src     : out std_logic;
        idex_alu_a_sel   : out std_logic;
        idex_reg_we      : out std_logic;
        idex_fp_reg_we   : out std_logic;
        idex_mem_we      : out std_logic;
        idex_mem_re      : out std_logic;
        idex_branch_op   : out std_logic_vector(3 downto 0);
        idex_wb_sel      : out std_logic_vector(2 downto 0);
        idex_mem_size    : out std_logic_vector(1 downto 0);
        idex_mem_unsigned: out std_logic;
        idex_valid       : out std_logic;
        idex_fp_en       : out std_logic;
        idex_fp_op       : out std_logic_vector(4 downto 0);
        idex_fp_rm       : out std_logic_vector(2 downto 0);
        idex_is_fp_load  : out std_logic;
        idex_is_fp_store : out std_logic
    );
end entity decode;

architecture rtl of decode is
    -- ALU ops
    constant ALU_ADD  : std_logic_vector(4 downto 0) := "00000";
    constant ALU_SUB  : std_logic_vector(4 downto 0) := "00001";
    constant ALU_AND  : std_logic_vector(4 downto 0) := "00010";
    constant ALU_OR   : std_logic_vector(4 downto 0) := "00011";
    constant ALU_XOR  : std_logic_vector(4 downto 0) := "00100";
    constant ALU_SLL  : std_logic_vector(4 downto 0) := "00101";
    constant ALU_SRL  : std_logic_vector(4 downto 0) := "00110";
    constant ALU_SRA  : std_logic_vector(4 downto 0) := "00111";
    constant ALU_SLT  : std_logic_vector(4 downto 0) := "01000";
    constant ALU_SLTU : std_logic_vector(4 downto 0) := "01001";
    constant ALU_PASSB: std_logic_vector(4 downto 0) := "01010";
    constant ALU_ADDW : std_logic_vector(4 downto 0) := "10000";
    constant ALU_SUBW : std_logic_vector(4 downto 0) := "10001";
    constant ALU_SLLW : std_logic_vector(4 downto 0) := "10101";
    constant ALU_SRLW : std_logic_vector(4 downto 0) := "10110";
    constant ALU_SRAW : std_logic_vector(4 downto 0) := "10111";

    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

    constant BR_NONE : std_logic_vector(3 downto 0) := x"0";
    constant BR_BEQ  : std_logic_vector(3 downto 0) := x"1";
    constant BR_BNE  : std_logic_vector(3 downto 0) := x"2";
    constant BR_JAL  : std_logic_vector(3 downto 0) := x"3";
    constant BR_JALR : std_logic_vector(3 downto 0) := x"4";
    constant BR_BLT  : std_logic_vector(3 downto 0) := x"5";
    constant BR_BGE  : std_logic_vector(3 downto 0) := x"6";
    constant BR_BLTU : std_logic_vector(3 downto 0) := x"7";
    constant BR_BGEU : std_logic_vector(3 downto 0) := x"8";

    constant WB_ALU : std_logic_vector(2 downto 0) := "000";
    constant WB_MEM : std_logic_vector(2 downto 0) := "001";
    constant WB_PC4 : std_logic_vector(2 downto 0) := "010";
    constant WB_FPU : std_logic_vector(2 downto 0) := "011";

    constant OP_RTYPE  : std_logic_vector(6 downto 0) := "0110011";
    constant OP_ITYPE  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_RW     : std_logic_vector(6 downto 0) := "0111011";
    constant OP_IW     : std_logic_vector(6 downto 0) := "0011011";
    constant OP_FP_LOAD  : std_logic_vector(6 downto 0) := "0000111";
    constant OP_FP_STORE : std_logic_vector(6 downto 0) := "0100111";
    constant OP_FP_OP    : std_logic_vector(6 downto 0) := "1010011";
    constant OP_FP_MADD  : std_logic_vector(6 downto 0) := "1000011";
    constant OP_FP_MSUB  : std_logic_vector(6 downto 0) := "1000111";
    constant OP_FP_NMSUB : std_logic_vector(6 downto 0) := "1001011";
    constant OP_FP_NMADD : std_logic_vector(6 downto 0) := "1001111";

    -- Instruction fields
    signal opcode : std_logic_vector(6 downto 0);
    signal rd_f   : std_logic_vector(4 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal rs1_f  : std_logic_vector(4 downto 0);
    signal rs2_f  : std_logic_vector(4 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);
    signal rs3_f  : std_logic_vector(4 downto 0);

    -- Register files
    type regfile_t is array (0 to 31) of std_logic_vector(63 downto 0);
    signal int_regfile : regfile_t := (others => (others => '0'));
    signal fp_regfile  : regfile_t := (others => (others => '0'));

    signal rs1_raw, rs2_raw : std_logic_vector(63 downto 0);
    signal fp_rs1_raw, fp_rs2_raw, fp_rs3_raw : std_logic_vector(63 downto 0);

    -- Control signals
    signal imm_type : std_logic_vector(2 downto 0);
    signal imm_val  : std_logic_vector(63 downto 0);
    signal ctrl_alu_op : std_logic_vector(4 downto 0);
    signal ctrl_alu_src, ctrl_alu_a_sel : std_logic;
    signal ctrl_reg_we, ctrl_fp_reg_we : std_logic;
    signal ctrl_mem_we, ctrl_mem_re : std_logic;
    signal ctrl_branch_op : std_logic_vector(3 downto 0);
    signal ctrl_wb_sel : std_logic_vector(2 downto 0);
    signal ctrl_mem_size : std_logic_vector(1 downto 0);
    signal ctrl_mem_unsigned : std_logic;
    signal ctrl_rs1_used, ctrl_rs2_used : std_logic;
    signal ctrl_fp_rs1_used, ctrl_fp_rs2_used, ctrl_fp_rs3_used : std_logic;
    signal ctrl_fp_en : std_logic;
    signal ctrl_fp_op : std_logic_vector(4 downto 0);
    signal ctrl_fp_rm : std_logic_vector(2 downto 0);
    signal ctrl_is_fp_load, ctrl_is_fp_store : std_logic;

    -- Forwarding
    signal rs1_fwd, rs2_fwd : std_logic_vector(63 downto 0);
    signal fp_rs1_fwd, fp_rs2_fwd, fp_rs3_fwd : std_logic_vector(63 downto 0);

    -- Internal pipeline regs
    signal idex_rs1_data_r, idex_rs2_data_r, idex_imm_r, idex_pc_r : std_logic_vector(63 downto 0);
    signal idex_fp_rs1_data_r, idex_fp_rs2_data_r, idex_fp_rs3_data_r : std_logic_vector(63 downto 0);
    signal idex_rd_r : std_logic_vector(4 downto 0);
    signal idex_alu_op_r : std_logic_vector(4 downto 0);
    signal idex_alu_src_r, idex_alu_a_sel_r : std_logic;
    signal idex_reg_we_r, idex_fp_reg_we_r : std_logic;
    signal idex_mem_we_r, idex_mem_re_r : std_logic;
    signal idex_branch_op_r : std_logic_vector(3 downto 0);
    signal idex_wb_sel_r : std_logic_vector(2 downto 0);
    signal idex_mem_size_r : std_logic_vector(1 downto 0);
    signal idex_mem_unsigned_r : std_logic;
    signal idex_valid_r : std_logic;
    signal idex_fp_en_r : std_logic;
    signal idex_fp_op_r : std_logic_vector(4 downto 0);
    signal idex_fp_rm_r : std_logic_vector(2 downto 0);
    signal idex_is_fp_load_r, idex_is_fp_store_r : std_logic;
begin

    opcode <= instr(6 downto 0);
    rd_f   <= instr(11 downto 7);
    funct3 <= instr(14 downto 12);
    rs1_f  <= instr(19 downto 15);
    rs2_f  <= instr(24 downto 20);
    funct7 <= instr(31 downto 25);
    rs3_f  <= instr(31 downto 27);

    -- Integer regfile
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                int_regfile <= (others => (others => '0'));
            elsif wb_reg_we = '1' and wb_rd /= "00000" then
                int_regfile(to_integer(unsigned(wb_rd))) <= wb_data;
            end if;
        end if;
    end process;

    rs1_raw <= (others => '0') when rs1_f = "00000" else int_regfile(to_integer(unsigned(rs1_f)));
    rs2_raw <= (others => '0') when rs2_f = "00000" else int_regfile(to_integer(unsigned(rs2_f)));

    -- FP regfile
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fp_regfile <= (others => (others => '0'));
            elsif wb_fp_reg_we = '1' then
                fp_regfile(to_integer(unsigned(wb_rd))) <= wb_fp_data;
            end if;
        end if;
    end process;

    fp_rs1_raw <= fp_regfile(to_integer(unsigned(rs1_f)));
    fp_rs2_raw <= fp_regfile(to_integer(unsigned(rs2_f)));
    fp_rs3_raw <= fp_regfile(to_integer(unsigned(rs3_f)));

    -- Immediate generator
    process(all)
    begin
        imm_val <= (others => '0');
        case imm_type is
            when IMM_I => imm_val <= (63 downto 12 => instr(31)) & instr(31 downto 20);
            when IMM_S => imm_val <= (63 downto 12 => instr(31)) & instr(31 downto 25) & instr(11 downto 7);
            when IMM_B => imm_val <= (63 downto 13 => instr(31)) & instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
            when IMM_U => imm_val <= (63 downto 32 => instr(31)) & instr(31 downto 12) & (11 downto 0 => '0');
            when IMM_J => imm_val <= (63 downto 21 => instr(31)) & instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
            when others => imm_val <= (others => '0');
        end case;
    end process;

    -- Control decode
    process(all)
    begin
        ctrl_alu_op <= ALU_ADD; ctrl_alu_src <= '0'; ctrl_alu_a_sel <= '0';
        ctrl_reg_we <= '0'; ctrl_fp_reg_we <= '0';
        ctrl_mem_we <= '0'; ctrl_mem_re <= '0';
        ctrl_branch_op <= BR_NONE; ctrl_wb_sel <= WB_ALU;
        ctrl_mem_size <= "11"; ctrl_mem_unsigned <= '0';
        imm_type <= IMM_I;
        ctrl_rs1_used <= '0'; ctrl_rs2_used <= '0';
        ctrl_fp_rs1_used <= '0'; ctrl_fp_rs2_used <= '0'; ctrl_fp_rs3_used <= '0';
        ctrl_fp_en <= '0'; ctrl_fp_op <= "00000"; ctrl_fp_rm <= "000";
        ctrl_is_fp_load <= '0'; ctrl_is_fp_store <= '0';

        case opcode is
            when OP_RTYPE =>
                ctrl_reg_we <= '1'; ctrl_rs1_used <= '1'; ctrl_rs2_used <= '1';
                case funct3 is
                    when "000" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SUB; else ctrl_alu_op <= ALU_ADD; end if;
                    when "001" => ctrl_alu_op <= ALU_SLL;
                    when "010" => ctrl_alu_op <= ALU_SLT;
                    when "011" => ctrl_alu_op <= ALU_SLTU;
                    when "100" => ctrl_alu_op <= ALU_XOR;
                    when "101" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SRA; else ctrl_alu_op <= ALU_SRL; end if;
                    when "110" => ctrl_alu_op <= ALU_OR;
                    when "111" => ctrl_alu_op <= ALU_AND;
                    when others => ctrl_alu_op <= ALU_ADD;
                end case;

            when OP_ITYPE =>
                ctrl_reg_we <= '1'; ctrl_alu_src <= '1'; ctrl_rs1_used <= '1'; imm_type <= IMM_I;
                case funct3 is
                    when "000" => ctrl_alu_op <= ALU_ADD;
                    when "001" => ctrl_alu_op <= ALU_SLL;
                    when "010" => ctrl_alu_op <= ALU_SLT;
                    when "011" => ctrl_alu_op <= ALU_SLTU;
                    when "100" => ctrl_alu_op <= ALU_XOR;
                    when "101" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SRA; else ctrl_alu_op <= ALU_SRL; end if;
                    when "110" => ctrl_alu_op <= ALU_OR;
                    when "111" => ctrl_alu_op <= ALU_AND;
                    when others => ctrl_alu_op <= ALU_ADD;
                end case;

            when OP_LOAD =>
                ctrl_reg_we <= '1'; ctrl_alu_src <= '1'; ctrl_alu_op <= ALU_ADD;
                ctrl_mem_re <= '1'; ctrl_wb_sel <= WB_MEM; ctrl_rs1_used <= '1'; imm_type <= IMM_I;
                case funct3 is
                    when "000" => ctrl_mem_size <= "00"; ctrl_mem_unsigned <= '0';
                    when "001" => ctrl_mem_size <= "01"; ctrl_mem_unsigned <= '0';
                    when "010" => ctrl_mem_size <= "10"; ctrl_mem_unsigned <= '0';
                    when "011" => ctrl_mem_size <= "11"; ctrl_mem_unsigned <= '0';
                    when "100" => ctrl_mem_size <= "00"; ctrl_mem_unsigned <= '1';
                    when "101" => ctrl_mem_size <= "01"; ctrl_mem_unsigned <= '1';
                    when "110" => ctrl_mem_size <= "10"; ctrl_mem_unsigned <= '1';
                    when others => ctrl_mem_size <= "11"; ctrl_mem_unsigned <= '0';
                end case;

            when OP_STORE =>
                ctrl_alu_src <= '1'; ctrl_alu_op <= ALU_ADD; ctrl_mem_we <= '1';
                ctrl_rs1_used <= '1'; ctrl_rs2_used <= '1'; imm_type <= IMM_S;
                case funct3 is
                    when "000" => ctrl_mem_size <= "00";
                    when "001" => ctrl_mem_size <= "01";
                    when "010" => ctrl_mem_size <= "10";
                    when "011" => ctrl_mem_size <= "11";
                    when others => ctrl_mem_size <= "11";
                end case;

            when OP_LUI =>
                ctrl_reg_we <= '1'; ctrl_alu_op <= ALU_PASSB; ctrl_alu_src <= '1'; imm_type <= IMM_U;

            when OP_AUIPC =>
                ctrl_reg_we <= '1'; ctrl_alu_op <= ALU_ADD; ctrl_alu_src <= '1'; ctrl_alu_a_sel <= '1'; imm_type <= IMM_U;

            when OP_JAL =>
                ctrl_reg_we <= '1'; ctrl_branch_op <= BR_JAL; ctrl_wb_sel <= WB_PC4;
                ctrl_alu_op <= ALU_ADD; ctrl_alu_a_sel <= '1'; ctrl_alu_src <= '1'; imm_type <= IMM_J;

            when OP_JALR =>
                ctrl_reg_we <= '1'; ctrl_branch_op <= BR_JALR; ctrl_wb_sel <= WB_PC4;
                ctrl_alu_op <= ALU_ADD; ctrl_alu_a_sel <= '1'; ctrl_alu_src <= '1';
                ctrl_rs1_used <= '1'; imm_type <= IMM_I;

            when OP_BRANCH =>
                ctrl_rs1_used <= '1'; ctrl_rs2_used <= '1'; imm_type <= IMM_B;
                case funct3 is
                    when "000" => ctrl_branch_op <= BR_BEQ;
                    when "001" => ctrl_branch_op <= BR_BNE;
                    when "100" => ctrl_branch_op <= BR_BLT;
                    when "101" => ctrl_branch_op <= BR_BGE;
                    when "110" => ctrl_branch_op <= BR_BLTU;
                    when "111" => ctrl_branch_op <= BR_BGEU;
                    when others => ctrl_branch_op <= BR_NONE;
                end case;

            when OP_RW =>
                ctrl_reg_we <= '1'; ctrl_rs1_used <= '1'; ctrl_rs2_used <= '1';
                case funct3 is
                    when "000" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SUBW; else ctrl_alu_op <= ALU_ADDW; end if;
                    when "001" => ctrl_alu_op <= ALU_SLLW;
                    when "101" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SRAW; else ctrl_alu_op <= ALU_SRLW; end if;
                    when others => ctrl_alu_op <= ALU_ADDW;
                end case;

            when OP_IW =>
                ctrl_reg_we <= '1'; ctrl_alu_src <= '1'; ctrl_rs1_used <= '1'; imm_type <= IMM_I;
                case funct3 is
                    when "000" => ctrl_alu_op <= ALU_ADDW;
                    when "001" => ctrl_alu_op <= ALU_SLLW;
                    when "101" => if funct7(5) = '1' then ctrl_alu_op <= ALU_SRAW; else ctrl_alu_op <= ALU_SRLW; end if;
                    when others => ctrl_alu_op <= ALU_ADDW;
                end case;

            when OP_FP_LOAD =>
                ctrl_alu_src <= '1'; ctrl_alu_op <= ALU_ADD; ctrl_mem_re <= '1'; ctrl_wb_sel <= WB_MEM;
                ctrl_rs1_used <= '1'; ctrl_is_fp_load <= '1'; ctrl_fp_reg_we <= '1';
                ctrl_mem_size <= "11"; imm_type <= IMM_I;

            when OP_FP_STORE =>
                ctrl_alu_src <= '1'; ctrl_alu_op <= ALU_ADD; ctrl_mem_we <= '1';
                ctrl_rs1_used <= '1'; ctrl_fp_rs2_used <= '1'; ctrl_is_fp_store <= '1';
                ctrl_mem_size <= "11"; imm_type <= IMM_S;

            when OP_FP_OP =>
                ctrl_fp_en <= '1'; ctrl_wb_sel <= WB_FPU;
                if funct3 = "111" then ctrl_fp_rm <= fcsr_frm; else ctrl_fp_rm <= funct3; end if;
                ctrl_fp_rs1_used <= '1'; ctrl_fp_rs2_used <= '1';
                case funct7(6 downto 2) is
                    when "00000" => ctrl_fp_op <= "00000"; ctrl_fp_reg_we <= '1'; -- FADD.D
                    when "00001" => ctrl_fp_op <= "00001"; ctrl_fp_reg_we <= '1'; -- FSUB.D
                    when "00010" => ctrl_fp_op <= "00010"; ctrl_fp_reg_we <= '1'; -- FMUL.D
                    when "00011" => ctrl_fp_op <= "00011"; ctrl_fp_reg_we <= '1'; -- FDIV.D
                    when "01011" => ctrl_fp_op <= "00100"; ctrl_fp_reg_we <= '1'; ctrl_fp_rs2_used <= '0'; -- FSQRT.D
                    when "00100" =>
                        ctrl_fp_reg_we <= '1';
                        case funct3 is
                            when "000" => ctrl_fp_op <= "01001"; -- FSGNJ
                            when "001" => ctrl_fp_op <= "01010"; -- FSGNJN
                            when "010" => ctrl_fp_op <= "01011"; -- FSGNJX
                            when others => ctrl_fp_op <= "01001";
                        end case;
                    when "00101" =>
                        ctrl_fp_reg_we <= '1';
                        case funct3 is
                            when "000" => ctrl_fp_op <= "01100"; -- FMIN
                            when "001" => ctrl_fp_op <= "01101"; -- FMAX
                            when others => ctrl_fp_op <= "01100";
                        end case;
                    when "10100" =>
                        ctrl_reg_we <= '1'; ctrl_fp_reg_we <= '0';
                        case funct3 is
                            when "010" => ctrl_fp_op <= "01110"; -- FEQ
                            when "001" => ctrl_fp_op <= "01111"; -- FLT
                            when "000" => ctrl_fp_op <= "10000"; -- FLE
                            when others => ctrl_fp_op <= "01110";
                        end case;
                    when "11000" =>
                        ctrl_reg_we <= '1'; ctrl_fp_reg_we <= '0'; ctrl_fp_rs2_used <= '0';
                        case rs2_f is
                            when "00000" => ctrl_fp_op <= "10001"; -- CVTWD
                            when "00001" => ctrl_fp_op <= "10010"; -- CVTWUD
                            when "00010" => ctrl_fp_op <= "10101"; -- CVTLD
                            when "00011" => ctrl_fp_op <= "10110"; -- CVTLUD
                            when others  => ctrl_fp_op <= "10001";
                        end case;
                    when "11010" =>
                        ctrl_fp_reg_we <= '1'; ctrl_fp_rs1_used <= '0'; ctrl_fp_rs2_used <= '0';
                        ctrl_rs1_used <= '1';
                        case rs2_f is
                            when "00000" => ctrl_fp_op <= "10011"; -- CVTDW
                            when "00001" => ctrl_fp_op <= "10100"; -- CVTDWU
                            when "00010" => ctrl_fp_op <= "10111"; -- CVTDL
                            when "00011" => ctrl_fp_op <= "11000"; -- CVTDLU
                            when others  => ctrl_fp_op <= "10011";
                        end case;
                    when "11100" =>
                        ctrl_reg_we <= '1'; ctrl_fp_reg_we <= '0'; ctrl_fp_rs2_used <= '0';
                        case funct3 is
                            when "000" => ctrl_fp_op <= "11010"; -- FMV.X.D
                            when "001" => ctrl_fp_op <= "11001"; -- FCLASS
                            when others => ctrl_fp_op <= "11010";
                        end case;
                    when "11110" =>
                        ctrl_fp_reg_we <= '1'; ctrl_fp_rs1_used <= '0'; ctrl_fp_rs2_used <= '0';
                        ctrl_rs1_used <= '1'; ctrl_fp_op <= "11011"; -- FMV.D.X
                    when others =>
                        ctrl_fp_en <= '0';
                end case;

            when OP_FP_MADD =>
                ctrl_fp_en <= '1'; ctrl_fp_op <= "00101"; ctrl_fp_reg_we <= '1'; ctrl_wb_sel <= WB_FPU;
                if funct3 = "111" then ctrl_fp_rm <= fcsr_frm; else ctrl_fp_rm <= funct3; end if;
                ctrl_fp_rs1_used <= '1'; ctrl_fp_rs2_used <= '1'; ctrl_fp_rs3_used <= '1';

            when OP_FP_MSUB =>
                ctrl_fp_en <= '1'; ctrl_fp_op <= "00110"; ctrl_fp_reg_we <= '1'; ctrl_wb_sel <= WB_FPU;
                if funct3 = "111" then ctrl_fp_rm <= fcsr_frm; else ctrl_fp_rm <= funct3; end if;
                ctrl_fp_rs1_used <= '1'; ctrl_fp_rs2_used <= '1'; ctrl_fp_rs3_used <= '1';

            when OP_FP_NMSUB =>
                ctrl_fp_en <= '1'; ctrl_fp_op <= "00111"; ctrl_fp_reg_we <= '1'; ctrl_wb_sel <= WB_FPU;
                if funct3 = "111" then ctrl_fp_rm <= fcsr_frm; else ctrl_fp_rm <= funct3; end if;
                ctrl_fp_rs1_used <= '1'; ctrl_fp_rs2_used <= '1'; ctrl_fp_rs3_used <= '1';

            when OP_FP_NMADD =>
                ctrl_fp_en <= '1'; ctrl_fp_op <= "01000"; ctrl_fp_reg_we <= '1'; ctrl_wb_sel <= WB_FPU;
                if funct3 = "111" then ctrl_fp_rm <= fcsr_frm; else ctrl_fp_rm <= funct3; end if;
                ctrl_fp_rs1_used <= '1'; ctrl_fp_rs2_used <= '1'; ctrl_fp_rs3_used <= '1';

            when others => null;
        end case;
    end process;

    -- Hazard unit outputs
    id_rs1_addr    <= rs1_f;
    id_rs2_addr    <= rs2_f;
    id_rs1_used    <= ctrl_rs1_used and ifid_valid;
    id_rs2_used    <= ctrl_rs2_used and ifid_valid;
    id_fp_rs1_addr <= rs1_f;
    id_fp_rs2_addr <= rs2_f;
    id_fp_rs3_addr <= rs3_f;
    id_fp_rs1_used <= ctrl_fp_rs1_used and ifid_valid;
    id_fp_rs2_used <= ctrl_fp_rs2_used and ifid_valid;
    id_fp_rs3_used <= ctrl_fp_rs3_used and ifid_valid;

    -- Integer forwarding (00=regfile, 01=EX comb, 10=EX/MEM, 11=MEM/WB)
    rs1_fwd <= ex_result    when fwd_rs1_sel = "01" else
               exmem_result when fwd_rs1_sel = "10" else
               memwb_result when fwd_rs1_sel = "11" else
               rs1_raw;
    rs2_fwd <= ex_result    when fwd_rs2_sel = "01" else
               exmem_result when fwd_rs2_sel = "10" else
               memwb_result when fwd_rs2_sel = "11" else
               rs2_raw;

    -- FP forwarding (00=regfile, 01=EX comb, 10=EX/MEM, 11=MEM/WB)
    fp_rs1_fwd <= ex_fp_result    when fwd_fp_rs1_sel = "01" else
                  exmem_fp_result when fwd_fp_rs1_sel = "10" else
                  memwb_fp_result when fwd_fp_rs1_sel = "11" else
                  fp_rs1_raw;
    fp_rs2_fwd <= ex_fp_result    when fwd_fp_rs2_sel = "01" else
                  exmem_fp_result when fwd_fp_rs2_sel = "10" else
                  memwb_fp_result when fwd_fp_rs2_sel = "11" else
                  fp_rs2_raw;
    fp_rs3_fwd <= ex_fp_result    when fwd_fp_rs3_sel = "01" else
                  exmem_fp_result when fwd_fp_rs3_sel = "10" else
                  memwb_fp_result when fwd_fp_rs3_sel = "11" else
                  fp_rs3_raw;

    -- Pipeline register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_id = '1' then
                idex_rs1_data_r <= (others => '0'); idex_rs2_data_r <= (others => '0');
                idex_imm_r <= (others => '0'); idex_pc_r <= (others => '0');
                idex_fp_rs1_data_r <= (others => '0'); idex_fp_rs2_data_r <= (others => '0');
                idex_fp_rs3_data_r <= (others => '0');
                idex_rd_r <= (others => '0'); idex_alu_op_r <= (others => '0');
                idex_alu_src_r <= '0'; idex_alu_a_sel_r <= '0';
                idex_reg_we_r <= '0'; idex_fp_reg_we_r <= '0';
                idex_mem_we_r <= '0'; idex_mem_re_r <= '0';
                idex_branch_op_r <= (others => '0'); idex_wb_sel_r <= (others => '0');
                idex_mem_size_r <= (others => '0'); idex_mem_unsigned_r <= '0';
                idex_valid_r <= '0'; idex_fp_en_r <= '0';
                idex_fp_op_r <= (others => '0'); idex_fp_rm_r <= (others => '0');
                idex_is_fp_load_r <= '0'; idex_is_fp_store_r <= '0';
            elsif stall_id = '0' then
                if ifid_valid = '1' then
                    idex_rs1_data_r <= rs1_fwd; idex_rs2_data_r <= rs2_fwd;
                    idex_imm_r <= imm_val; idex_pc_r <= ifid_pc;
                    idex_fp_rs1_data_r <= fp_rs1_fwd; idex_fp_rs2_data_r <= fp_rs2_fwd;
                    idex_fp_rs3_data_r <= fp_rs3_fwd;
                    idex_rd_r <= rd_f; idex_alu_op_r <= ctrl_alu_op;
                    idex_alu_src_r <= ctrl_alu_src; idex_alu_a_sel_r <= ctrl_alu_a_sel;
                    idex_reg_we_r <= ctrl_reg_we; idex_fp_reg_we_r <= ctrl_fp_reg_we;
                    idex_mem_we_r <= ctrl_mem_we; idex_mem_re_r <= ctrl_mem_re;
                    idex_branch_op_r <= ctrl_branch_op; idex_wb_sel_r <= ctrl_wb_sel;
                    idex_mem_size_r <= ctrl_mem_size; idex_mem_unsigned_r <= ctrl_mem_unsigned;
                    idex_valid_r <= '1'; idex_fp_en_r <= ctrl_fp_en;
                    idex_fp_op_r <= ctrl_fp_op; idex_fp_rm_r <= ctrl_fp_rm;
                    idex_is_fp_load_r <= ctrl_is_fp_load; idex_is_fp_store_r <= ctrl_is_fp_store;
                else
                    idex_reg_we_r <= '0'; idex_fp_reg_we_r <= '0';
                    idex_mem_we_r <= '0'; idex_mem_re_r <= '0';
                    idex_branch_op_r <= BR_NONE; idex_valid_r <= '0';
                    idex_fp_en_r <= '0'; idex_is_fp_load_r <= '0'; idex_is_fp_store_r <= '0';
                end if;
            end if;
        end if;
    end process;

    idex_rs1_data <= idex_rs1_data_r; idex_rs2_data <= idex_rs2_data_r;
    idex_imm <= idex_imm_r; idex_pc <= idex_pc_r;
    idex_fp_rs1_data <= idex_fp_rs1_data_r; idex_fp_rs2_data <= idex_fp_rs2_data_r;
    idex_fp_rs3_data <= idex_fp_rs3_data_r;
    idex_rd <= idex_rd_r; idex_alu_op <= idex_alu_op_r;
    idex_alu_src <= idex_alu_src_r; idex_alu_a_sel <= idex_alu_a_sel_r;
    idex_reg_we <= idex_reg_we_r; idex_fp_reg_we <= idex_fp_reg_we_r;
    idex_mem_we <= idex_mem_we_r; idex_mem_re <= idex_mem_re_r;
    idex_branch_op <= idex_branch_op_r; idex_wb_sel <= idex_wb_sel_r;
    idex_mem_size <= idex_mem_size_r; idex_mem_unsigned <= idex_mem_unsigned_r;
    idex_valid <= idex_valid_r; idex_fp_en <= idex_fp_en_r;
    idex_fp_op <= idex_fp_op_r; idex_fp_rm <= idex_fp_rm_r;
    idex_is_fp_load <= idex_is_fp_load_r; idex_is_fp_store <= idex_is_fp_store_r;

end architecture rtl;
