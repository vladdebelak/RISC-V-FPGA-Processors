-- rv16_core.vhd
-- 16-bit 3-stage pipelined RISC-V core (Fetch / Decode / Execute)
-- No hardware hazard detection -- software must insert NOPs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv16_core is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;

        -- Instruction memory interface
        instr_addr : out std_logic_vector(7 downto 0);  -- word index into instr_mem (256 entries)
        instr_data : in  std_logic_vector(31 downto 0); -- instruction fetched from BRAM

        -- Data memory interface
        mem_addr   : out std_logic_vector(15 downto 0);
        mem_wdata  : out std_logic_vector(15 downto 0);
        mem_rdata  : in  std_logic_vector(15 downto 0);
        mem_we     : out std_logic;
        mem_re     : out std_logic
    );
end entity rv16_core;

architecture rtl of rv16_core is

    -- Stall / flush
    signal stall : std_logic;
    signal flush : std_logic;

    -- Fetch -> Decode
    signal pc_out     : std_logic_vector(15 downto 0);
    signal ifde_pc    : std_logic_vector(15 downto 0);
    signal ifde_valid : std_logic;

    -- Branch feedback (Execute -> Fetch)
    signal branch_taken  : std_logic;
    signal branch_target : std_logic_vector(15 downto 0);

    -- Writeback feedback (Execute -> Decode)
    signal wb_rd   : std_logic_vector(3 downto 0);
    signal wb_data : std_logic_vector(15 downto 0);
    signal wb_we   : std_logic;

    -- Decode -> Execute (pipeline register outputs)
    signal deex_alu_op    : std_logic_vector(3 downto 0);
    signal deex_rs1_data  : std_logic_vector(15 downto 0);
    signal deex_rs2_data  : std_logic_vector(15 downto 0);
    signal deex_rd        : std_logic_vector(3 downto 0);
    signal deex_reg_we    : std_logic;
    signal deex_mem_we    : std_logic;
    signal deex_mem_re    : std_logic;
    signal deex_branch_op : std_logic_vector(1 downto 0);
    signal deex_alu_src   : std_logic;
    signal deex_wb_sel    : std_logic_vector(1 downto 0);
    signal deex_pc        : std_logic_vector(15 downto 0);
    signal deex_imm       : std_logic_vector(15 downto 0);
    signal deex_valid     : std_logic;

begin

    -- No hardware interlock; NOP-padded SW
    stall <= '0';
    flush <= branch_taken;

    -- Instruction address (byte PC -> word index, 8 bits)
    instr_addr <= pc_out(9 downto 2);

    -- Stage 1 -- Fetch
    u_fetch : entity work.fetch
        port map (
            clk           => clk,
            rst           => rst,
            stall         => stall,
            flush         => flush,
            branch_taken  => branch_taken,
            branch_target => branch_target,
            pc_out        => pc_out,
            ifde_pc       => ifde_pc,
            ifde_valid    => ifde_valid
        );

    -- Stage 2 -- Decode
    u_decode : entity work.decode
        port map (
            clk            => clk,
            rst            => rst,
            stall          => stall,
            flush          => flush,
            instr          => instr_data,
            ifde_pc        => ifde_pc,
            ifde_valid     => ifde_valid,
            wb_rd          => wb_rd,
            wb_data        => wb_data,
            wb_we          => wb_we,
            deex_alu_op    => deex_alu_op,
            deex_rs1_data  => deex_rs1_data,
            deex_rs2_data  => deex_rs2_data,
            deex_rd        => deex_rd,
            deex_reg_we    => deex_reg_we,
            deex_mem_we    => deex_mem_we,
            deex_mem_re    => deex_mem_re,
            deex_branch_op => deex_branch_op,
            deex_alu_src   => deex_alu_src,
            deex_wb_sel    => deex_wb_sel,
            deex_pc        => deex_pc,
            deex_imm       => deex_imm,
            deex_valid     => deex_valid
        );

    -- Stage 3 -- Execute
    u_execute : entity work.execute
        port map (
            clk            => clk,
            rst            => rst,
            deex_alu_op    => deex_alu_op,
            deex_rs1_data  => deex_rs1_data,
            deex_rs2_data  => deex_rs2_data,
            deex_rd        => deex_rd,
            deex_reg_we    => deex_reg_we,
            deex_mem_we    => deex_mem_we,
            deex_mem_re    => deex_mem_re,
            deex_branch_op => deex_branch_op,
            deex_alu_src   => deex_alu_src,
            deex_wb_sel    => deex_wb_sel,
            deex_pc        => deex_pc,
            deex_imm       => deex_imm,
            deex_valid     => deex_valid,
            mem_rdata      => mem_rdata,
            mem_addr       => mem_addr,
            mem_wdata      => mem_wdata,
            mem_we         => mem_we,
            mem_re         => mem_re,
            branch_taken   => branch_taken,
            branch_target  => branch_target,
            wb_rd          => wb_rd,
            wb_data        => wb_data,
            wb_we          => wb_we
        );

end architecture rtl;
