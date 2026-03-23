-- decode.vhd — DE stage for 3-stage RV64I pipeline
-- Full RV64I control decode, register file, immediate generation

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decode is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        stall            : in  std_logic;
        flush            : in  std_logic;
        instr            : in  std_logic_vector(31 downto 0);
        ifde_pc          : in  std_logic_vector(63 downto 0);
        ifde_valid       : in  std_logic;
        -- Writeback port
        wb_rd            : in  std_logic_vector(4 downto 0);
        wb_data          : in  std_logic_vector(63 downto 0);
        wb_we            : in  std_logic;
        -- DE/EX pipeline outputs
        deex_rs1_data    : out std_logic_vector(63 downto 0);
        deex_rs2_data    : out std_logic_vector(63 downto 0);
        deex_imm         : out std_logic_vector(63 downto 0);
        deex_pc          : out std_logic_vector(63 downto 0);
        deex_rd          : out std_logic_vector(4 downto 0);
        deex_alu_op      : out std_logic_vector(4 downto 0);
        deex_alu_src     : out std_logic;
        deex_alu_a_sel   : out std_logic;
        deex_reg_we      : out std_logic;
        deex_mem_we      : out std_logic;
        deex_mem_re      : out std_logic;
        deex_branch_op   : out std_logic_vector(3 downto 0);
        deex_wb_sel      : out std_logic_vector(1 downto 0);
        deex_mem_size    : out std_logic_vector(1 downto 0);
        deex_mem_unsigned : out std_logic;
        deex_valid       : out std_logic
    );
end entity decode;

architecture rtl of decode is

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

    -- Immediate types (3-bit)
    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";

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

    -- Opcodes (7-bit)
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

    -- Instruction field extraction
    signal opcode  : std_logic_vector(6 downto 0);
    signal funct3  : std_logic_vector(2 downto 0);
    signal funct7  : std_logic_vector(6 downto 0);
    signal rs1_addr : std_logic_vector(4 downto 0);
    signal rs2_addr : std_logic_vector(4 downto 0);
    signal rd_addr  : std_logic_vector(4 downto 0);

    -- Register file
    type regfile_type is array (0 to 31) of std_logic_vector(63 downto 0);
    signal regfile : regfile_type := (others => (others => '0'));

    signal rs1_data : std_logic_vector(63 downto 0);
    signal rs2_data : std_logic_vector(63 downto 0);

    -- Immediate
    signal imm_type : std_logic_vector(2 downto 0);
    signal imm_out  : std_logic_vector(63 downto 0);

    -- Control signals
    signal ctrl_alu_op       : std_logic_vector(4 downto 0);
    signal ctrl_alu_src      : std_logic;
    signal ctrl_alu_a_sel    : std_logic;
    signal ctrl_reg_we       : std_logic;
    signal ctrl_mem_we       : std_logic;
    signal ctrl_mem_re       : std_logic;
    signal ctrl_branch_op    : std_logic_vector(3 downto 0);
    signal ctrl_wb_sel       : std_logic_vector(1 downto 0);
    signal ctrl_mem_size     : std_logic_vector(1 downto 0);
    signal ctrl_mem_unsigned : std_logic;

begin

    -- Instruction field extraction
    opcode   <= instr(6 downto 0);
    funct3   <= instr(14 downto 12);
    funct7   <= instr(31 downto 25);
    rs1_addr <= instr(19 downto 15);
    rs2_addr <= instr(24 downto 20);
    rd_addr  <= instr(11 downto 7);

    -- Register read (x0 hardwired to 0)
    rs1_data <= (others => '0') when rs1_addr = "00000" else regfile(to_integer(unsigned(rs1_addr)));
    rs2_data <= (others => '0') when rs2_addr = "00000" else regfile(to_integer(unsigned(rs2_addr)));

    -- Register write
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                for i in 0 to 31 loop
                    regfile(i) <= (others => '0');
                end loop;
            elsif wb_we = '1' and wb_rd /= "00000" then
                regfile(to_integer(unsigned(wb_rd))) <= wb_data;
            end if;
        end if;
    end process;

    -- Immediate generator (combinational)
    process (all)
    begin
        imm_out <= (others => '0');
        case imm_type is
            when IMM_I =>
                imm_out <= (63 downto 12 => instr(31)) & instr(31 downto 20);
            when IMM_S =>
                imm_out <= (63 downto 12 => instr(31)) & instr(31 downto 25) & instr(11 downto 7);
            when IMM_B =>
                imm_out <= (63 downto 13 => instr(31)) & instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
            when IMM_U =>
                imm_out <= (63 downto 32 => instr(31)) & instr(31 downto 12) & x"000";
            when IMM_J =>
                imm_out <= (63 downto 21 => instr(31)) & instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
            when others =>
                imm_out <= (others => '0');
        end case;
    end process;

    -- Control decode (combinational)
    process (all)
    begin
        -- Defaults (NOP)
        ctrl_alu_op       <= ALU_ADD;
        ctrl_alu_src      <= '0';
        ctrl_alu_a_sel    <= '0';
        ctrl_reg_we       <= '0';
        ctrl_mem_we       <= '0';
        ctrl_mem_re       <= '0';
        ctrl_branch_op    <= BR_NONE;
        ctrl_wb_sel       <= WB_ALU;
        ctrl_mem_size     <= "00";
        ctrl_mem_unsigned <= '0';
        imm_type          <= IMM_I;

        case opcode is
            -- R-type
            when OP_RTYPE =>
                ctrl_alu_src <= '0';
                ctrl_reg_we  <= '1';
                ctrl_wb_sel  <= WB_ALU;
                case funct3 is
                    when "000" =>
                        if funct7(5) = '1' then ctrl_alu_op <= ALU_SUB;
                        else                     ctrl_alu_op <= ALU_ADD;
                        end if;
                    when "001" => ctrl_alu_op <= ALU_SLL;
                    when "010" => ctrl_alu_op <= ALU_SLT;
                    when "011" => ctrl_alu_op <= ALU_SLTU;
                    when "100" => ctrl_alu_op <= ALU_XOR;
                    when "101" =>
                        if funct7(5) = '1' then ctrl_alu_op <= ALU_SRA;
                        else                     ctrl_alu_op <= ALU_SRL;
                        end if;
                    when "110" => ctrl_alu_op <= ALU_OR;
                    when "111" => ctrl_alu_op <= ALU_AND;
                    when others => ctrl_alu_op <= ALU_ADD;
                end case;

            -- I-type ALU
            when OP_ITYPE =>
                ctrl_alu_src <= '1';
                ctrl_reg_we  <= '1';
                ctrl_wb_sel  <= WB_ALU;
                imm_type     <= IMM_I;
                case funct3 is
                    when "000" => ctrl_alu_op <= ALU_ADD;
                    when "010" => ctrl_alu_op <= ALU_SLT;
                    when "011" => ctrl_alu_op <= ALU_SLTU;
                    when "100" => ctrl_alu_op <= ALU_XOR;
                    when "110" => ctrl_alu_op <= ALU_OR;
                    when "111" => ctrl_alu_op <= ALU_AND;
                    when "001" => ctrl_alu_op <= ALU_SLL;
                    when "101" =>
                        if instr(30) = '1' then ctrl_alu_op <= ALU_SRA;
                        else                     ctrl_alu_op <= ALU_SRL;
                        end if;
                    when others => ctrl_alu_op <= ALU_ADD;
                end case;

            -- R-type word (ADDW, SUBW, SLLW, SRLW, SRAW)
            when OP_RW =>
                ctrl_alu_src <= '0';
                ctrl_reg_we  <= '1';
                ctrl_wb_sel  <= WB_ALU;
                case funct3 is
                    when "000" =>
                        if funct7(5) = '1' then ctrl_alu_op <= ALU_SUBW;
                        else                     ctrl_alu_op <= ALU_ADDW;
                        end if;
                    when "001" => ctrl_alu_op <= ALU_SLLW;
                    when "101" =>
                        if funct7(5) = '1' then ctrl_alu_op <= ALU_SRAW;
                        else                     ctrl_alu_op <= ALU_SRLW;
                        end if;
                    when others => ctrl_alu_op <= ALU_ADDW;
                end case;

            -- I-type word (ADDIW, SLLIW, SRLIW, SRAIW)
            when OP_IW =>
                ctrl_alu_src <= '1';
                ctrl_reg_we  <= '1';
                ctrl_wb_sel  <= WB_ALU;
                imm_type     <= IMM_I;
                case funct3 is
                    when "000" => ctrl_alu_op <= ALU_ADDW;
                    when "001" => ctrl_alu_op <= ALU_SLLW;
                    when "101" =>
                        if instr(30) = '1' then ctrl_alu_op <= ALU_SRAW;
                        else                     ctrl_alu_op <= ALU_SRLW;
                        end if;
                    when others => ctrl_alu_op <= ALU_ADDW;
                end case;

            -- Load
            when OP_LOAD =>
                ctrl_alu_op  <= ALU_ADD;
                ctrl_alu_src <= '1';
                ctrl_reg_we  <= '1';
                ctrl_mem_re  <= '1';
                ctrl_wb_sel  <= WB_MEM;
                imm_type     <= IMM_I;
                case funct3 is
                    when "000" => ctrl_mem_size <= "00"; ctrl_mem_unsigned <= '0'; -- LB
                    when "001" => ctrl_mem_size <= "01"; ctrl_mem_unsigned <= '0'; -- LH
                    when "010" => ctrl_mem_size <= "10"; ctrl_mem_unsigned <= '0'; -- LW
                    when "011" => ctrl_mem_size <= "11"; ctrl_mem_unsigned <= '0'; -- LD
                    when "100" => ctrl_mem_size <= "00"; ctrl_mem_unsigned <= '1'; -- LBU
                    when "101" => ctrl_mem_size <= "01"; ctrl_mem_unsigned <= '1'; -- LHU
                    when "110" => ctrl_mem_size <= "10"; ctrl_mem_unsigned <= '1'; -- LWU
                    when others => ctrl_mem_size <= "00"; ctrl_mem_unsigned <= '0';
                end case;

            -- Store
            when OP_STORE =>
                ctrl_alu_op  <= ALU_ADD;
                ctrl_alu_src <= '1';
                ctrl_reg_we  <= '0';
                ctrl_mem_we  <= '1';
                imm_type     <= IMM_S;
                case funct3 is
                    when "000" => ctrl_mem_size <= "00"; -- SB
                    when "001" => ctrl_mem_size <= "01"; -- SH
                    when "010" => ctrl_mem_size <= "10"; -- SW
                    when "011" => ctrl_mem_size <= "11"; -- SD
                    when others => ctrl_mem_size <= "00";
                end case;

            -- LUI
            when OP_LUI =>
                ctrl_alu_op  <= ALU_PASS_B;
                ctrl_alu_src <= '1';
                ctrl_reg_we  <= '1';
                ctrl_wb_sel  <= WB_ALU;
                imm_type     <= IMM_U;

            -- AUIPC
            when OP_AUIPC =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_a_sel <= '1';
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '1';
                ctrl_wb_sel    <= WB_ALU;
                imm_type       <= IMM_U;

            -- JAL
            when OP_JAL =>
                ctrl_reg_we    <= '1';
                ctrl_branch_op <= BR_JAL;
                ctrl_wb_sel    <= WB_PC4;
                imm_type       <= IMM_J;

            -- JALR
            when OP_JALR =>
                ctrl_alu_op    <= ALU_ADD;
                ctrl_alu_src   <= '1';
                ctrl_reg_we    <= '1';
                ctrl_branch_op <= BR_JALR;
                ctrl_wb_sel    <= WB_PC4;
                imm_type       <= IMM_I;

            -- Branch
            when OP_BRANCH =>
                ctrl_alu_src <= '0';
                ctrl_reg_we  <= '0';
                imm_type     <= IMM_B;
                case funct3 is
                    when "000" => ctrl_branch_op <= BR_BEQ;
                    when "001" => ctrl_branch_op <= BR_BNE;
                    when "100" => ctrl_branch_op <= BR_BLT;
                    when "101" => ctrl_branch_op <= BR_BGE;
                    when "110" => ctrl_branch_op <= BR_BLTU;
                    when "111" => ctrl_branch_op <= BR_BGEU;
                    when others => ctrl_branch_op <= BR_NONE;
                end case;

            -- Default: NOP
            when others =>
                ctrl_alu_op       <= ALU_ADD;
                ctrl_alu_src      <= '0';
                ctrl_alu_a_sel    <= '0';
                ctrl_reg_we       <= '0';
                ctrl_mem_we       <= '0';
                ctrl_mem_re       <= '0';
                ctrl_branch_op    <= BR_NONE;
                ctrl_wb_sel       <= WB_ALU;
                ctrl_mem_size     <= "00";
                ctrl_mem_unsigned <= '0';
                imm_type          <= IMM_I;
        end case;
    end process;

    -- DE/EX pipeline register
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                deex_rs1_data     <= (others => '0');
                deex_rs2_data     <= (others => '0');
                deex_imm          <= (others => '0');
                deex_pc           <= (others => '0');
                deex_rd           <= (others => '0');
                deex_alu_op       <= (others => '0');
                deex_alu_src      <= '0';
                deex_alu_a_sel    <= '0';
                deex_reg_we       <= '0';
                deex_mem_we       <= '0';
                deex_mem_re       <= '0';
                deex_branch_op    <= (others => '0');
                deex_wb_sel       <= (others => '0');
                deex_mem_size     <= (others => '0');
                deex_mem_unsigned <= '0';
                deex_valid        <= '0';
            elsif stall = '0' then
                if ifde_valid = '1' then
                    deex_rs1_data     <= rs1_data;
                    deex_rs2_data     <= rs2_data;
                    deex_imm          <= imm_out;
                    deex_pc           <= ifde_pc;
                    deex_rd           <= rd_addr;
                    deex_alu_op       <= ctrl_alu_op;
                    deex_alu_src      <= ctrl_alu_src;
                    deex_alu_a_sel    <= ctrl_alu_a_sel;
                    deex_reg_we       <= ctrl_reg_we;
                    deex_mem_we       <= ctrl_mem_we;
                    deex_mem_re       <= ctrl_mem_re;
                    deex_branch_op    <= ctrl_branch_op;
                    deex_wb_sel       <= ctrl_wb_sel;
                    deex_mem_size     <= ctrl_mem_size;
                    deex_mem_unsigned <= ctrl_mem_unsigned;
                    deex_valid        <= '1';
                else
                    -- Bubble: invalidate pipeline stage
                    deex_rs1_data     <= (others => '0');
                    deex_rs2_data     <= (others => '0');
                    deex_imm          <= (others => '0');
                    deex_pc           <= (others => '0');
                    deex_rd           <= (others => '0');
                    deex_alu_op       <= (others => '0');
                    deex_alu_src      <= '0';
                    deex_alu_a_sel    <= '0';
                    deex_reg_we       <= '0';
                    deex_mem_we       <= '0';
                    deex_mem_re       <= '0';
                    deex_branch_op    <= (others => '0');
                    deex_wb_sel       <= (others => '0');
                    deex_mem_size     <= (others => '0');
                    deex_mem_unsigned <= '0';
                    deex_valid        <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
