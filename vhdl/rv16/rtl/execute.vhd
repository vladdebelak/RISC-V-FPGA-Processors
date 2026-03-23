-- execute.vhd -- Stage 3: ALU, branch resolution, memory interface, writeback
-- 16-bit 3-stage RISC-V microcontroller

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity execute is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        -- From DE/EX pipeline register
        deex_rs1_data  : in  std_logic_vector(15 downto 0);
        deex_rs2_data  : in  std_logic_vector(15 downto 0);
        deex_imm       : in  std_logic_vector(15 downto 0);
        deex_pc        : in  std_logic_vector(15 downto 0);
        deex_rd        : in  std_logic_vector(3 downto 0);
        deex_alu_op    : in  std_logic_vector(3 downto 0);
        deex_alu_src   : in  std_logic;
        deex_reg_we    : in  std_logic;
        deex_mem_we    : in  std_logic;
        deex_mem_re    : in  std_logic;
        deex_branch_op : in  std_logic_vector(1 downto 0);
        deex_wb_sel    : in  std_logic_vector(1 downto 0);
        deex_valid     : in  std_logic;
        -- Memory interface
        mem_addr       : out std_logic_vector(15 downto 0);
        mem_wdata      : out std_logic_vector(15 downto 0);
        mem_rdata      : in  std_logic_vector(15 downto 0);
        mem_we         : out std_logic;
        mem_re         : out std_logic;
        -- Branch output (to fetch stage)
        branch_taken   : out std_logic;
        branch_target  : out std_logic_vector(15 downto 0);
        -- Writeback output (to decode regfile)
        wb_rd          : out std_logic_vector(3 downto 0);
        wb_data        : out std_logic_vector(15 downto 0);
        wb_we          : out std_logic
    );
end entity execute;

architecture rtl of execute is

    constant BR_NONE : std_logic_vector(1 downto 0) := "00";
    constant BR_BEQ  : std_logic_vector(1 downto 0) := "01";
    constant BR_BNE  : std_logic_vector(1 downto 0) := "10";
    constant BR_JAL  : std_logic_vector(1 downto 0) := "11";

    constant WB_ALU : std_logic_vector(1 downto 0) := "00";
    constant WB_MEM : std_logic_vector(1 downto 0) := "01";
    constant WB_PC4 : std_logic_vector(1 downto 0) := "10";

    -- ALU signals
    signal alu_b      : std_logic_vector(15 downto 0);
    signal alu_result : std_logic_vector(15 downto 0);
    signal alu_zero   : std_logic;

    -- Branch
    signal branch_taken_r : std_logic;

    -- Writeback
    signal wb_data_r : std_logic_vector(15 downto 0);

begin

    -- ALU input mux
    alu_b <= deex_imm when deex_alu_src = '1' else deex_rs2_data;

    -- ALU instance
    u_alu : entity work.alu
        port map (
            a      => deex_rs1_data,
            b      => alu_b,
            alu_op => deex_alu_op,
            result => alu_result,
            zero   => alu_zero
        );

    -- Branch resolution (combinational)
    branch_target <= std_logic_vector(unsigned(deex_pc) + unsigned(deex_imm));

    process (all)
    begin
        branch_taken_r <= '0';
        if deex_valid = '1' then
            case deex_branch_op is
                when BR_JAL  => branch_taken_r <= '1';
                when BR_BEQ  => branch_taken_r <= alu_zero;
                when BR_BNE  => branch_taken_r <= not alu_zero;
                when others  => branch_taken_r <= '0';
            end case;
        end if;
    end process;

    branch_taken <= branch_taken_r;

    -- Memory interface
    mem_addr  <= alu_result;
    mem_wdata <= deex_rs2_data;
    mem_we    <= deex_mem_we and deex_valid;
    mem_re    <= deex_mem_re and deex_valid;

    -- Writeback mux (combinational)
    process (all)
    begin
        wb_data_r <= alu_result;
        case deex_wb_sel is
            when WB_ALU  => wb_data_r <= alu_result;
            when WB_MEM  => wb_data_r <= mem_rdata;
            when WB_PC4  => wb_data_r <= std_logic_vector(unsigned(deex_pc) + to_unsigned(4, 16));
            when others  => wb_data_r <= alu_result;
        end case;
    end process;

    wb_data <= wb_data_r;
    wb_rd   <= deex_rd;
    wb_we   <= deex_reg_we and deex_valid;

end architecture rtl;
