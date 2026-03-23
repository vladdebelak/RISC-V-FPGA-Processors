library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity writeback is
    port (
        memwb_alu_result : in  std_logic_vector(63 downto 0);
        memwb_mem_rdata  : in  std_logic_vector(63 downto 0);
        memwb_rd         : in  std_logic_vector(4 downto 0);
        memwb_reg_we     : in  std_logic;
        memwb_fp_reg_we  : in  std_logic;
        memwb_wb_sel     : in  std_logic_vector(2 downto 0);
        memwb_valid      : in  std_logic;
        memwb_is_fp_load : in  std_logic;
        wb_rd            : out std_logic_vector(4 downto 0);
        wb_data          : out std_logic_vector(63 downto 0);
        wb_reg_we        : out std_logic;
        wb_fp_reg_we     : out std_logic;
        wb_fp_data       : out std_logic_vector(63 downto 0)
    );
end entity writeback;

architecture rtl of writeback is
    constant WB_ALU : std_logic_vector(2 downto 0) := "000";
    constant WB_MEM : std_logic_vector(2 downto 0) := "001";
    constant WB_PC4 : std_logic_vector(2 downto 0) := "010";
    constant WB_FPU : std_logic_vector(2 downto 0) := "011";

    signal wb_data_mux : std_logic_vector(63 downto 0);
begin

    process(all)
    begin
        case memwb_wb_sel is
            when WB_ALU =>
                wb_data_mux <= memwb_alu_result;
            when WB_MEM =>
                wb_data_mux <= memwb_mem_rdata;
            when WB_PC4 =>
                wb_data_mux <= memwb_alu_result;
            when WB_FPU =>
                wb_data_mux <= memwb_alu_result;
            when others =>
                wb_data_mux <= memwb_alu_result;
        end case;
    end process;

    wb_rd       <= memwb_rd;
    wb_data     <= wb_data_mux;
    wb_reg_we   <= memwb_reg_we and memwb_valid;
    wb_fp_reg_we <= (memwb_fp_reg_we or memwb_is_fp_load) and memwb_valid;
    wb_fp_data  <= memwb_mem_rdata when memwb_is_fp_load = '1' else memwb_alu_result;

end architecture rtl;
