-- rv64_core.vhd — RV64I pipeline shell (fetch / decode / execute)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv64_core is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- Instruction memory
        instr_addr   : out std_logic_vector(8 downto 0);
        instr_data   : in  std_logic_vector(31 downto 0);
        -- Data memory / bus
        mem_addr     : out std_logic_vector(63 downto 0);
        mem_wdata    : out std_logic_vector(63 downto 0);
        mem_rdata    : in  std_logic_vector(63 downto 0);
        mem_we       : out std_logic;
        mem_re       : out std_logic;
        mem_size     : out std_logic_vector(1 downto 0);
        mem_unsigned : out std_logic
    );
end entity rv64_core;

architecture rtl of rv64_core is

    -- Fetch outputs
    signal pc_out     : std_logic_vector(63 downto 0);
    signal ifde_pc    : std_logic_vector(63 downto 0);
    signal ifde_valid : std_logic;

    -- Decode outputs
    signal deex_pc           : std_logic_vector(63 downto 0);
    signal deex_valid        : std_logic;
    signal deex_rd           : std_logic_vector(4 downto 0);
    signal deex_rs1_data     : std_logic_vector(63 downto 0);
    signal deex_rs2_data     : std_logic_vector(63 downto 0);
    signal deex_imm          : std_logic_vector(63 downto 0);
    signal deex_alu_src      : std_logic;
    signal deex_alu_a_sel    : std_logic;
    signal deex_alu_op       : std_logic_vector(4 downto 0);
    signal deex_mem_we       : std_logic;
    signal deex_mem_re       : std_logic;
    signal deex_reg_we       : std_logic;
    signal deex_branch_op    : std_logic_vector(3 downto 0);
    signal deex_wb_sel       : std_logic_vector(1 downto 0);
    signal deex_mem_size     : std_logic_vector(1 downto 0);
    signal deex_mem_unsigned : std_logic;

    -- Execute -> fetch
    signal branch_taken  : std_logic;
    signal branch_target : std_logic_vector(63 downto 0);
    signal jalr_taken    : std_logic;
    signal jalr_target   : std_logic_vector(63 downto 0);

    -- Execute -> decode (write-back)
    signal wb_rd   : std_logic_vector(4 downto 0);
    signal wb_data : std_logic_vector(63 downto 0);
    signal wb_we   : std_logic;

    -- Pipeline control
    signal flush : std_logic;
    signal stall : std_logic;

begin

    flush <= branch_taken or jalr_taken;
    stall <= '0';  -- NOP padding eliminates hazards

    -- Instruction address = PC word index (bits [10:2])
    instr_addr <= pc_out(10 downto 2);

    -- Fetch stage
    u_fetch: entity work.fetch
        port map (
            clk           => clk,
            rst           => rst,
            stall         => stall,
            flush         => flush,
            branch_taken  => branch_taken,
            branch_target => branch_target,
            jalr_taken    => jalr_taken,
            jalr_target   => jalr_target,
            pc_out        => pc_out,
            ifde_pc       => ifde_pc,
            ifde_valid    => ifde_valid
        );

    -- Decode stage
    u_decode: entity work.decode
        port map (
            clk               => clk,
            rst               => rst,
            stall             => stall,
            flush             => flush,
            instr             => instr_data,
            ifde_pc           => ifde_pc,
            ifde_valid        => ifde_valid,
            wb_rd             => wb_rd,
            wb_data           => wb_data,
            wb_we             => wb_we,
            deex_rs1_data     => deex_rs1_data,
            deex_rs2_data     => deex_rs2_data,
            deex_imm          => deex_imm,
            deex_pc           => deex_pc,
            deex_rd           => deex_rd,
            deex_alu_op       => deex_alu_op,
            deex_alu_src      => deex_alu_src,
            deex_alu_a_sel    => deex_alu_a_sel,
            deex_reg_we       => deex_reg_we,
            deex_mem_we       => deex_mem_we,
            deex_mem_re       => deex_mem_re,
            deex_branch_op    => deex_branch_op,
            deex_wb_sel       => deex_wb_sel,
            deex_mem_size     => deex_mem_size,
            deex_mem_unsigned => deex_mem_unsigned,
            deex_valid        => deex_valid
        );

    -- Execute stage
    u_execute: entity work.execute
        port map (
            clk               => clk,
            rst               => rst,
            deex_rs1_data     => deex_rs1_data,
            deex_rs2_data     => deex_rs2_data,
            deex_imm          => deex_imm,
            deex_pc           => deex_pc,
            deex_rd           => deex_rd,
            deex_alu_op       => deex_alu_op,
            deex_alu_src      => deex_alu_src,
            deex_alu_a_sel    => deex_alu_a_sel,
            deex_reg_we       => deex_reg_we,
            deex_mem_we       => deex_mem_we,
            deex_mem_re       => deex_mem_re,
            deex_branch_op    => deex_branch_op,
            deex_wb_sel       => deex_wb_sel,
            deex_mem_size     => deex_mem_size,
            deex_mem_unsigned => deex_mem_unsigned,
            deex_valid        => deex_valid,
            mem_addr          => mem_addr,
            mem_wdata         => mem_wdata,
            mem_rdata         => mem_rdata,
            mem_we            => mem_we,
            mem_re            => mem_re,
            mem_size          => mem_size,
            mem_unsigned      => mem_unsigned,
            branch_taken      => branch_taken,
            branch_target     => branch_target,
            jalr_taken        => jalr_taken,
            jalr_target       => jalr_target,
            wb_rd             => wb_rd,
            wb_data           => wb_data,
            wb_we             => wb_we
        );

end architecture rtl;
