library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reset_sync is
    port (
        clk      : in  std_logic;
        rst_btn  : in  std_logic;
        rst_sync : out std_logic
    );
end entity reset_sync;

architecture rtl of reset_sync is
    attribute ASYNC_REG : string;
    signal sync_ff0 : std_logic;
    signal sync_ff1 : std_logic;
    attribute ASYNC_REG of sync_ff0 : signal is "TRUE";
    attribute ASYNC_REG of sync_ff1 : signal is "TRUE";
begin

    process(clk, rst_btn)
    begin
        if rst_btn = '1' then
            sync_ff0 <= '1';
            sync_ff1 <= '1';
        elsif rising_edge(clk) then
            sync_ff0 <= '0';
            sync_ff1 <= sync_ff0;
        end if;
    end process;

    rst_sync <= sync_ff1;

end architecture rtl;
