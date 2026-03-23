library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fcsr is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        we         : in  std_logic;
        wr_frm     : in  std_logic_vector(2 downto 0);
        wr_fflags  : in  std_logic_vector(4 downto 0);
        we_flags   : in  std_logic;
        fpu_flags  : in  std_logic_vector(4 downto 0);
        frm        : out std_logic_vector(2 downto 0);
        fflags     : out std_logic_vector(4 downto 0)
    );
end entity fcsr;

architecture rtl of fcsr is
    signal frm_reg    : std_logic_vector(2 downto 0);
    signal fflags_reg : std_logic_vector(4 downto 0);
begin

    frm    <= frm_reg;
    fflags <= fflags_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                frm_reg    <= "000";
                fflags_reg <= "00000";
            else
                if we = '1' then
                    frm_reg    <= wr_frm;
                    fflags_reg <= wr_fflags;
                end if;
                if we_flags = '1' then
                    fflags_reg <= fflags_reg or fpu_flags;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
