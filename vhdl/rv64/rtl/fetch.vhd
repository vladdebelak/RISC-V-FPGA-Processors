-- fetch.vhd — IF stage for 3-stage RV64I pipeline
-- 64-bit PC with IF/DE pipeline register

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fetch is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        stall         : in  std_logic;
        flush         : in  std_logic;
        branch_taken  : in  std_logic;
        branch_target : in  std_logic_vector(63 downto 0);
        jalr_taken    : in  std_logic;
        jalr_target   : in  std_logic_vector(63 downto 0);

        pc_out        : out std_logic_vector(63 downto 0);
        ifde_pc       : out std_logic_vector(63 downto 0);
        ifde_valid    : out std_logic
    );
end entity fetch;

architecture rtl of fetch is
    signal pc_reg      : std_logic_vector(63 downto 0);
    signal ifde_pc_r   : std_logic_vector(63 downto 0);
    signal ifde_valid_r : std_logic;
begin

    -- PC update
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc_reg <= (others => '0');
            elsif jalr_taken = '1' then
                pc_reg <= jalr_target;
            elsif branch_taken = '1' then
                pc_reg <= branch_target;
            elsif stall = '0' then
                pc_reg <= std_logic_vector(unsigned(pc_reg) + to_unsigned(4, 64));
            end if;
        end if;
    end process;

    pc_out <= pc_reg;

    -- IF/DE pipeline register
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                ifde_pc_r    <= (others => '0');
                ifde_valid_r <= '0';
            elsif stall = '0' then
                ifde_pc_r    <= pc_reg;
                ifde_valid_r <= '1';
            end if;
        end if;
    end process;

    ifde_pc    <= ifde_pc_r;
    ifde_valid <= ifde_valid_r;

end architecture rtl;
