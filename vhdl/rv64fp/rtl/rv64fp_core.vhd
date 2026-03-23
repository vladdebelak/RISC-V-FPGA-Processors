library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv64fp_core is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        instr_addr   : out std_logic_vector(8 downto 0);
        instr_data   : in  std_logic_vector(31 downto 0);
        mem_addr     : out std_logic_vector(63 downto 0);
        mem_wdata    : out std_logic_vector(63 downto 0);
        mem_rdata    : in  std_logic_vector(63 downto 0);
        mem_we       : out std_logic;
        mem_re       : out std_logic;
        mem_size     : out std_logic_vector(1 downto 0);
        mem_unsigned : out std_logic
    );
end entity rv64fp_core;

architecture rtl of rv64fp_core is
    -- Fetch
    signal pc_out : std_logic_vector(63 downto 0);
    signal ifid_pc : std_logic_vector(63 downto 0);
    signal ifid_valid : std_logic;

    -- Decode
    signal id_rs1_addr, id_rs2_addr : std_logic_vector(4 downto 0);
    signal id_rs1_used, id_rs2_used : std_logic;
    signal id_fp_rs1_addr, id_fp_rs2_addr, id_fp_rs3_addr : std_logic_vector(4 downto 0);
    signal id_fp_rs1_used, id_fp_rs2_used, id_fp_rs3_used : std_logic;
    signal idex_pc, idex_rs1_data, idex_rs2_data, idex_imm : std_logic_vector(63 downto 0);
    signal idex_rd : std_logic_vector(4 downto 0);
    signal idex_alu_op : std_logic_vector(4 downto 0);
    signal idex_alu_src, idex_alu_a_sel : std_logic;
    signal idex_reg_we, idex_mem_re, idex_mem_we : std_logic;
    signal idex_mem_size : std_logic_vector(1 downto 0);
    signal idex_mem_unsigned : std_logic;
    signal idex_branch_op : std_logic_vector(3 downto 0);
    signal idex_wb_sel : std_logic_vector(2 downto 0);
    signal idex_valid : std_logic;
    signal idex_fp_reg_we, idex_fp_en : std_logic;
    signal idex_fp_op : std_logic_vector(4 downto 0);
    signal idex_fp_rm : std_logic_vector(2 downto 0);
    signal idex_fp_rs1_data, idex_fp_rs2_data, idex_fp_rs3_data : std_logic_vector(63 downto 0);
    signal idex_is_fp_load, idex_is_fp_store : std_logic;

    -- Execute
    signal ex_branch_taken : std_logic;
    signal ex_branch_target : std_logic_vector(63 downto 0);
    signal ex_jalr_taken : std_logic;
    signal ex_jalr_target : std_logic_vector(63 downto 0);
    signal exmem_rd : std_logic_vector(4 downto 0);
    signal exmem_alu_result, exmem_rs2_data : std_logic_vector(63 downto 0);
    signal exmem_reg_we, exmem_mem_re, exmem_mem_we : std_logic;
    signal exmem_wb_sel : std_logic_vector(2 downto 0);
    signal exmem_mem_size : std_logic_vector(1 downto 0);
    signal exmem_mem_unsigned : std_logic;
    signal exmem_valid : std_logic;
    signal exmem_fp_reg_we : std_logic;
    signal exmem_is_fp_load, exmem_is_fp_store : std_logic;
    signal fpu_busy : std_logic;
    signal fpu_flags : std_logic_vector(4 downto 0);
    signal fpu_done : std_logic;

    -- FCSR
    signal fcsr_frm : std_logic_vector(2 downto 0);
    signal fcsr_fflags : std_logic_vector(4 downto 0);

    -- Memory
    signal memwb_rd : std_logic_vector(4 downto 0);
    signal memwb_alu_result, memwb_mem_rdata : std_logic_vector(63 downto 0);
    signal memwb_reg_we, memwb_fp_reg_we : std_logic;
    signal memwb_wb_sel : std_logic_vector(2 downto 0);
    signal memwb_valid : std_logic;
    signal memwb_is_fp_load : std_logic;

    -- Writeback
    signal wb_rd : std_logic_vector(4 downto 0);
    signal wb_data : std_logic_vector(63 downto 0);
    signal wb_reg_we, wb_fp_reg_we : std_logic;
    signal wb_fp_data : std_logic_vector(63 downto 0);

    -- Hazard
    signal fwd_rs1_sel, fwd_rs2_sel : std_logic_vector(1 downto 0);
    signal fwd_fp_rs1_sel, fwd_fp_rs2_sel, fwd_fp_rs3_sel : std_logic_vector(1 downto 0);
    signal stall_if, stall_id, stall_ex : std_logic;
    signal flush_if, flush_id, flush_ex : std_logic;

    -- Combinational EX results (for 1-cycle-ahead forwarding)
    signal ex_result_comb : std_logic_vector(63 downto 0);
    signal ex_fp_result_comb : std_logic_vector(63 downto 0);

    -- Forwarded results
    signal exmem_result, memwb_result : std_logic_vector(63 downto 0);
    signal exmem_fp_result_fwd, memwb_fp_result_fwd : std_logic_vector(63 downto 0);
begin

    instr_addr <= pc_out(10 downto 2);

    exmem_result        <= exmem_alu_result;
    memwb_result        <= wb_data;
    exmem_fp_result_fwd <= exmem_alu_result;
    memwb_fp_result_fwd <= wb_fp_data;

    u_fetch: entity work.fetch
        port map (clk => clk, rst => rst, stall_if => stall_if, flush_if => flush_if,
                  branch_taken => ex_branch_taken, branch_target => ex_branch_target,
                  jalr_taken => ex_jalr_taken, jalr_target => ex_jalr_target,
                  pc_out => pc_out, ifid_pc => ifid_pc, ifid_valid => ifid_valid);

    u_decode: entity work.decode
        port map (clk => clk, rst => rst, stall_id => stall_id, flush_id => flush_id,
                  fcsr_frm => fcsr_frm, instr => instr_data, ifid_pc => ifid_pc, ifid_valid => ifid_valid,
                  wb_rd => wb_rd, wb_data => wb_data, wb_reg_we => wb_reg_we,
                  wb_fp_reg_we => wb_fp_reg_we, wb_fp_data => wb_fp_data,
                  fwd_rs1_sel => fwd_rs1_sel, fwd_rs2_sel => fwd_rs2_sel,
                  fwd_fp_rs1_sel => fwd_fp_rs1_sel, fwd_fp_rs2_sel => fwd_fp_rs2_sel,
                  fwd_fp_rs3_sel => fwd_fp_rs3_sel,
                  ex_result => ex_result_comb,
                  exmem_result => exmem_result, memwb_result => memwb_result,
                  ex_fp_result => ex_fp_result_comb,
                  exmem_fp_result => exmem_fp_result_fwd, memwb_fp_result => memwb_fp_result_fwd,
                  id_rs1_addr => id_rs1_addr, id_rs2_addr => id_rs2_addr,
                  id_rs1_used => id_rs1_used, id_rs2_used => id_rs2_used,
                  id_fp_rs1_addr => id_fp_rs1_addr, id_fp_rs2_addr => id_fp_rs2_addr,
                  id_fp_rs3_addr => id_fp_rs3_addr,
                  id_fp_rs1_used => id_fp_rs1_used, id_fp_rs2_used => id_fp_rs2_used,
                  id_fp_rs3_used => id_fp_rs3_used,
                  idex_pc => idex_pc, idex_rs1_data => idex_rs1_data, idex_rs2_data => idex_rs2_data,
                  idex_imm => idex_imm, idex_rd => idex_rd, idex_alu_op => idex_alu_op,
                  idex_alu_src => idex_alu_src, idex_alu_a_sel => idex_alu_a_sel,
                  idex_reg_we => idex_reg_we, idex_mem_re => idex_mem_re, idex_mem_we => idex_mem_we,
                  idex_mem_size => idex_mem_size, idex_mem_unsigned => idex_mem_unsigned,
                  idex_branch_op => idex_branch_op, idex_wb_sel => idex_wb_sel, idex_valid => idex_valid,
                  idex_fp_reg_we => idex_fp_reg_we, idex_fp_en => idex_fp_en,
                  idex_fp_op => idex_fp_op, idex_fp_rm => idex_fp_rm,
                  idex_fp_rs1_data => idex_fp_rs1_data, idex_fp_rs2_data => idex_fp_rs2_data,
                  idex_fp_rs3_data => idex_fp_rs3_data,
                  idex_is_fp_load => idex_is_fp_load, idex_is_fp_store => idex_is_fp_store);

    u_execute: entity work.execute
        port map (clk => clk, rst => rst, stall_ex => stall_ex, flush_ex => flush_ex,
                  idex_rs1_data => idex_rs1_data, idex_rs2_data => idex_rs2_data,
                  idex_imm => idex_imm, idex_pc => idex_pc,
                  idex_fp_rs1_data => idex_fp_rs1_data, idex_fp_rs2_data => idex_fp_rs2_data,
                  idex_fp_rs3_data => idex_fp_rs3_data,
                  idex_rd => idex_rd, idex_alu_op => idex_alu_op,
                  idex_alu_src => idex_alu_src, idex_alu_a_sel => idex_alu_a_sel,
                  idex_reg_we => idex_reg_we, idex_fp_reg_we => idex_fp_reg_we,
                  idex_mem_we => idex_mem_we, idex_mem_re => idex_mem_re,
                  idex_branch_op => idex_branch_op, idex_wb_sel => idex_wb_sel,
                  idex_mem_size => idex_mem_size, idex_mem_unsigned => idex_mem_unsigned,
                  idex_valid => idex_valid, idex_fp_en => idex_fp_en,
                  idex_fp_op => idex_fp_op, idex_fp_rm => idex_fp_rm,
                  idex_is_fp_load => idex_is_fp_load, idex_is_fp_store => idex_is_fp_store,
                  branch_taken => ex_branch_taken, branch_target => ex_branch_target,
                  jalr_taken => ex_jalr_taken, jalr_target => ex_jalr_target,
                  fpu_busy => fpu_busy, fpu_flags_out => fpu_flags, fpu_done => fpu_done,
                  ex_result_comb => ex_result_comb, ex_fp_result_comb => ex_fp_result_comb,
                  exmem_rd => exmem_rd, exmem_alu_result => exmem_alu_result,
                  exmem_rs2_data => exmem_rs2_data, exmem_reg_we => exmem_reg_we,
                  exmem_fp_reg_we => exmem_fp_reg_we,
                  exmem_mem_we => exmem_mem_we, exmem_mem_re => exmem_mem_re,
                  exmem_wb_sel => exmem_wb_sel, exmem_mem_size => exmem_mem_size,
                  exmem_mem_unsigned => exmem_mem_unsigned, exmem_valid => exmem_valid,
                  exmem_is_fp_load => exmem_is_fp_load, exmem_is_fp_store => exmem_is_fp_store);

    u_memory: entity work.memory
        port map (clk => clk, rst => rst,
                  exmem_alu_result => exmem_alu_result, exmem_rs2_data => exmem_rs2_data,
                  exmem_rd => exmem_rd, exmem_reg_we => exmem_reg_we,
                  exmem_fp_reg_we => exmem_fp_reg_we,
                  exmem_mem_we => exmem_mem_we, exmem_mem_re => exmem_mem_re,
                  exmem_wb_sel => exmem_wb_sel, exmem_mem_size => exmem_mem_size,
                  exmem_mem_unsigned => exmem_mem_unsigned, exmem_valid => exmem_valid,
                  exmem_is_fp_load => exmem_is_fp_load, exmem_is_fp_store => exmem_is_fp_store,
                  mem_addr => mem_addr, mem_wdata => mem_wdata, mem_rdata => mem_rdata,
                  mem_we => mem_we, mem_re => mem_re, mem_size => mem_size, mem_unsigned => mem_unsigned,
                  memwb_rd => memwb_rd, memwb_alu_result => memwb_alu_result,
                  memwb_mem_rdata => memwb_mem_rdata, memwb_reg_we => memwb_reg_we,
                  memwb_fp_reg_we => memwb_fp_reg_we, memwb_wb_sel => memwb_wb_sel,
                  memwb_valid => memwb_valid, memwb_is_fp_load => memwb_is_fp_load);

    u_writeback: entity work.writeback
        port map (memwb_alu_result => memwb_alu_result, memwb_mem_rdata => memwb_mem_rdata,
                  memwb_rd => memwb_rd, memwb_reg_we => memwb_reg_we,
                  memwb_fp_reg_we => memwb_fp_reg_we, memwb_wb_sel => memwb_wb_sel,
                  memwb_valid => memwb_valid, memwb_is_fp_load => memwb_is_fp_load,
                  wb_rd => wb_rd, wb_data => wb_data, wb_reg_we => wb_reg_we,
                  wb_fp_reg_we => wb_fp_reg_we, wb_fp_data => wb_fp_data);

    u_fcsr: entity work.fcsr
        port map (clk => clk, rst => rst, we => '0', wr_frm => "000", wr_fflags => "00000",
                  we_flags => fpu_done, fpu_flags => fpu_flags,
                  frm => fcsr_frm, fflags => fcsr_fflags);

    u_hazard: entity work.hazard_unit
        port map (id_rs1_addr => id_rs1_addr, id_rs2_addr => id_rs2_addr,
                  id_rs1_used => id_rs1_used, id_rs2_used => id_rs2_used,
                  -- From ID/EX (instruction in EX stage)
                  idex_rd => idex_rd, idex_reg_we => idex_reg_we,
                  idex_fp_reg_we => idex_fp_reg_we, idex_mem_re => idex_mem_re,
                  -- From EX/MEM
                  exmem_rd => exmem_rd, exmem_reg_we => exmem_reg_we,
                  exmem_fp_reg_we => exmem_fp_reg_we, exmem_mem_re => exmem_mem_re,
                  -- From MEM/WB
                  memwb_rd => memwb_rd, memwb_reg_we => memwb_reg_we,
                  memwb_fp_reg_we => memwb_fp_reg_we,
                  id_fp_rs1_addr => id_fp_rs1_addr, id_fp_rs2_addr => id_fp_rs2_addr,
                  id_fp_rs3_addr => id_fp_rs3_addr,
                  id_fp_rs1_used => id_fp_rs1_used, id_fp_rs2_used => id_fp_rs2_used,
                  id_fp_rs3_used => id_fp_rs3_used,
                  fpu_busy => fpu_busy, branch_taken => ex_branch_taken, jalr_taken => ex_jalr_taken,
                  fwd_rs1_sel => fwd_rs1_sel, fwd_rs2_sel => fwd_rs2_sel,
                  fwd_fp_rs1_sel => fwd_fp_rs1_sel, fwd_fp_rs2_sel => fwd_fp_rs2_sel,
                  fwd_fp_rs3_sel => fwd_fp_rs3_sel,
                  stall_if => stall_if, stall_id => stall_id, stall_ex => stall_ex,
                  flush_if => flush_if, flush_id => flush_id, flush_ex => flush_ex);

end architecture rtl;
