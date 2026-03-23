library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fetch is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        stall_if      : in  std_logic;
        flush_if      : in  std_logic;
        branch_taken  : in  std_logic;
        branch_target : in  std_logic_vector(63 downto 0);
        jalr_taken    : in  std_logic;
        jalr_target   : in  std_logic_vector(63 downto 0);
        pc_out        : out std_logic_vector(63 downto 0);
        ifid_pc       : out std_logic_vector(63 downto 0);
        ifid_valid    : out std_logic
    );
end entity fetch;

architecture rtl of fetch is
    signal pc_reg      : unsigned(63 downto 0);
    signal ifid_pc_r   : std_logic_vector(63 downto 0);
    signal ifid_valid_r: std_logic;
begin

    -- PC Register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc_reg <= (others => '0');
            elsif jalr_taken = '1' then
                pc_reg <= unsigned(jalr_target);
            elsif branch_taken = '1' then
                pc_reg <= unsigned(branch_target);
            elsif stall_if = '0' then
                pc_reg <= pc_reg + 4;
            end if;
        end if;
    end process;

    -- PC Output
    pc_out <= std_logic_vector(pc_reg);

    -- IF/ID Pipeline Register
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_if = '1' then
                ifid_pc_r    <= (others => '0');
                ifid_valid_r <= '0';
            elsif stall_if = '0' then
                ifid_pc_r    <= std_logic_vector(pc_reg);
                ifid_valid_r <= '1';
            end if;
        end if;
    end process;

    ifid_pc    <= ifid_pc_r;
    ifid_valid <= ifid_valid_r;

end architecture rtl;
