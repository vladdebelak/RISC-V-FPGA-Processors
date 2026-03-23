library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        exmem_alu_result : in  std_logic_vector(63 downto 0);
        exmem_rs2_data   : in  std_logic_vector(63 downto 0);
        exmem_rd         : in  std_logic_vector(4 downto 0);
        exmem_reg_we     : in  std_logic;
        exmem_fp_reg_we  : in  std_logic;
        exmem_mem_we     : in  std_logic;
        exmem_mem_re     : in  std_logic;
        exmem_wb_sel     : in  std_logic_vector(2 downto 0);
        exmem_mem_size   : in  std_logic_vector(1 downto 0);
        exmem_mem_unsigned : in std_logic;
        exmem_valid      : in  std_logic;
        exmem_is_fp_load : in  std_logic;
        exmem_is_fp_store: in  std_logic;
        mem_addr         : out std_logic_vector(63 downto 0);
        mem_wdata        : out std_logic_vector(63 downto 0);
        mem_rdata        : in  std_logic_vector(63 downto 0);
        mem_we           : out std_logic;
        mem_re           : out std_logic;
        mem_size         : out std_logic_vector(1 downto 0);
        mem_unsigned     : out std_logic;
        memwb_alu_result : out std_logic_vector(63 downto 0);
        memwb_mem_rdata  : out std_logic_vector(63 downto 0);
        memwb_rd         : out std_logic_vector(4 downto 0);
        memwb_reg_we     : out std_logic;
        memwb_fp_reg_we  : out std_logic;
        memwb_wb_sel     : out std_logic_vector(2 downto 0);
        memwb_valid      : out std_logic;
        memwb_is_fp_load : out std_logic
    );
end entity memory;

architecture rtl of memory is
    signal memwb_alu_result_r : std_logic_vector(63 downto 0);
    signal memwb_mem_rdata_r  : std_logic_vector(63 downto 0);
    signal memwb_rd_r         : std_logic_vector(4 downto 0);
    signal memwb_reg_we_r     : std_logic;
    signal memwb_fp_reg_we_r  : std_logic;
    signal memwb_wb_sel_r     : std_logic_vector(2 downto 0);
    signal memwb_valid_r      : std_logic;
    signal memwb_is_fp_load_r : std_logic;
begin

    mem_addr     <= exmem_alu_result;
    mem_wdata    <= exmem_rs2_data;
    mem_we       <= exmem_mem_we and exmem_valid;
    mem_re       <= exmem_mem_re and exmem_valid;
    mem_size     <= exmem_mem_size;
    mem_unsigned <= exmem_mem_unsigned;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                memwb_alu_result_r <= (others => '0');
                memwb_mem_rdata_r  <= (others => '0');
                memwb_rd_r         <= (others => '0');
                memwb_reg_we_r     <= '0';
                memwb_fp_reg_we_r  <= '0';
                memwb_wb_sel_r     <= (others => '0');
                memwb_valid_r      <= '0';
                memwb_is_fp_load_r <= '0';
            else
                memwb_alu_result_r <= exmem_alu_result;
                memwb_mem_rdata_r  <= mem_rdata;
                memwb_rd_r         <= exmem_rd;
                memwb_reg_we_r     <= exmem_reg_we;
                memwb_fp_reg_we_r  <= exmem_fp_reg_we;
                memwb_wb_sel_r     <= exmem_wb_sel;
                memwb_valid_r      <= exmem_valid;
                memwb_is_fp_load_r <= exmem_is_fp_load;
            end if;
        end if;
    end process;

    memwb_alu_result <= memwb_alu_result_r;
    memwb_mem_rdata  <= memwb_mem_rdata_r;
    memwb_rd         <= memwb_rd_r;
    memwb_reg_we     <= memwb_reg_we_r;
    memwb_fp_reg_we  <= memwb_fp_reg_we_r;
    memwb_wb_sel     <= memwb_wb_sel_r;
    memwb_valid      <= memwb_valid_r;
    memwb_is_fp_load <= memwb_is_fp_load_r;

end architecture rtl;
