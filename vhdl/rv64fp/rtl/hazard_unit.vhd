library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hazard_unit is
    port (
        id_rs1_addr     : in  std_logic_vector(4 downto 0);
        id_rs2_addr     : in  std_logic_vector(4 downto 0);
        id_rs1_used     : in  std_logic;
        id_rs2_used     : in  std_logic;
        -- From ID/EX pipeline register (instruction in EX stage)
        idex_rd         : in  std_logic_vector(4 downto 0);
        idex_reg_we     : in  std_logic;
        idex_fp_reg_we  : in  std_logic;
        idex_mem_re     : in  std_logic;
        -- From EX/MEM pipeline register
        exmem_rd        : in  std_logic_vector(4 downto 0);
        exmem_reg_we    : in  std_logic;
        exmem_fp_reg_we : in  std_logic;
        exmem_mem_re    : in  std_logic;
        -- From MEM/WB pipeline register
        memwb_rd        : in  std_logic_vector(4 downto 0);
        memwb_reg_we    : in  std_logic;
        memwb_fp_reg_we : in  std_logic;
        -- FP source addresses from decode
        id_fp_rs1_addr  : in  std_logic_vector(4 downto 0);
        id_fp_rs2_addr  : in  std_logic_vector(4 downto 0);
        id_fp_rs3_addr  : in  std_logic_vector(4 downto 0);
        id_fp_rs1_used  : in  std_logic;
        id_fp_rs2_used  : in  std_logic;
        id_fp_rs3_used  : in  std_logic;
        fpu_busy        : in  std_logic;
        branch_taken    : in  std_logic;
        jalr_taken      : in  std_logic;
        -- Forwarding select outputs (00=regfile, 01=EX/comb, 10=exmem, 11=memwb)
        fwd_rs1_sel     : out std_logic_vector(1 downto 0);
        fwd_rs2_sel     : out std_logic_vector(1 downto 0);
        fwd_fp_rs1_sel  : out std_logic_vector(1 downto 0);
        fwd_fp_rs2_sel  : out std_logic_vector(1 downto 0);
        fwd_fp_rs3_sel  : out std_logic_vector(1 downto 0);
        stall_if        : out std_logic;
        stall_id        : out std_logic;
        stall_ex        : out std_logic;
        flush_if        : out std_logic;
        flush_id        : out std_logic;
        flush_ex        : out std_logic
    );
end entity hazard_unit;

architecture rtl of hazard_unit is
    signal load_use_idex  : std_logic;
    signal load_use_exmem : std_logic;
    signal load_use_hazard : std_logic;
begin

    -- Load-use hazard: load in EX stage (idex)
    load_use_idex <= idex_mem_re when (
        (id_rs1_used = '1' and idex_rd = id_rs1_addr and idex_rd /= "00000") or
        (id_rs2_used = '1' and idex_rd = id_rs2_addr and idex_rd /= "00000") or
        (id_fp_rs1_used = '1' and idex_rd = id_fp_rs1_addr) or
        (id_fp_rs2_used = '1' and idex_rd = id_fp_rs2_addr) or
        (id_fp_rs3_used = '1' and idex_rd = id_fp_rs3_addr)
    ) else '0';

    -- Load-use hazard: load in MEM stage (exmem)
    load_use_exmem <= exmem_mem_re when (
        (id_rs1_used = '1' and exmem_rd = id_rs1_addr and exmem_rd /= "00000") or
        (id_rs2_used = '1' and exmem_rd = id_rs2_addr and exmem_rd /= "00000") or
        (id_fp_rs1_used = '1' and exmem_rd = id_fp_rs1_addr) or
        (id_fp_rs2_used = '1' and exmem_rd = id_fp_rs2_addr) or
        (id_fp_rs3_used = '1' and exmem_rd = id_fp_rs3_addr)
    ) else '0';

    load_use_hazard <= load_use_idex or load_use_exmem;

    -- Integer forwarding rs1
    -- Priority: EX (idex, 01) > MEM (exmem, 10) > WB (memwb, 11)
    process(all)
    begin
        fwd_rs1_sel <= "00";
        if idex_reg_we = '1' and idex_rd /= "00000" and idex_rd = id_rs1_addr and id_rs1_used = '1' and idex_mem_re = '0' then
            fwd_rs1_sel <= "01";
        elsif exmem_reg_we = '1' and exmem_rd /= "00000" and exmem_rd = id_rs1_addr and id_rs1_used = '1' then
            fwd_rs1_sel <= "10";
        elsif memwb_reg_we = '1' and memwb_rd /= "00000" and memwb_rd = id_rs1_addr and id_rs1_used = '1' then
            fwd_rs1_sel <= "11";
        end if;
    end process;

    -- Integer forwarding rs2
    process(all)
    begin
        fwd_rs2_sel <= "00";
        if idex_reg_we = '1' and idex_rd /= "00000" and idex_rd = id_rs2_addr and id_rs2_used = '1' and idex_mem_re = '0' then
            fwd_rs2_sel <= "01";
        elsif exmem_reg_we = '1' and exmem_rd /= "00000" and exmem_rd = id_rs2_addr and id_rs2_used = '1' then
            fwd_rs2_sel <= "10";
        elsif memwb_reg_we = '1' and memwb_rd /= "00000" and memwb_rd = id_rs2_addr and id_rs2_used = '1' then
            fwd_rs2_sel <= "11";
        end if;
    end process;

    -- FP forwarding rs1
    -- Priority: EX (01) > MEM (10) > WB (11)
    process(all)
    begin
        fwd_fp_rs1_sel <= "00";
        if idex_fp_reg_we = '1' and idex_rd = id_fp_rs1_addr and id_fp_rs1_used = '1' then
            fwd_fp_rs1_sel <= "01";
        elsif exmem_fp_reg_we = '1' and exmem_rd = id_fp_rs1_addr and id_fp_rs1_used = '1' then
            fwd_fp_rs1_sel <= "10";
        elsif memwb_fp_reg_we = '1' and memwb_rd = id_fp_rs1_addr and id_fp_rs1_used = '1' then
            fwd_fp_rs1_sel <= "11";
        end if;
    end process;

    -- FP forwarding rs2
    process(all)
    begin
        fwd_fp_rs2_sel <= "00";
        if idex_fp_reg_we = '1' and idex_rd = id_fp_rs2_addr and id_fp_rs2_used = '1' then
            fwd_fp_rs2_sel <= "01";
        elsif exmem_fp_reg_we = '1' and exmem_rd = id_fp_rs2_addr and id_fp_rs2_used = '1' then
            fwd_fp_rs2_sel <= "10";
        elsif memwb_fp_reg_we = '1' and memwb_rd = id_fp_rs2_addr and id_fp_rs2_used = '1' then
            fwd_fp_rs2_sel <= "11";
        end if;
    end process;

    -- FP forwarding rs3
    process(all)
    begin
        fwd_fp_rs3_sel <= "00";
        if idex_fp_reg_we = '1' and idex_rd = id_fp_rs3_addr and id_fp_rs3_used = '1' then
            fwd_fp_rs3_sel <= "01";
        elsif exmem_fp_reg_we = '1' and exmem_rd = id_fp_rs3_addr and id_fp_rs3_used = '1' then
            fwd_fp_rs3_sel <= "10";
        elsif memwb_fp_reg_we = '1' and memwb_rd = id_fp_rs3_addr and id_fp_rs3_used = '1' then
            fwd_fp_rs3_sel <= "11";
        end if;
    end process;

    -- Stall and flush generation
    stall_if <= load_use_hazard or fpu_busy;
    stall_id <= load_use_hazard or fpu_busy;
    stall_ex <= fpu_busy;

    flush_if <= branch_taken or jalr_taken;
    flush_id <= branch_taken or jalr_taken;
    flush_ex <= load_use_hazard;

end architecture rtl;
