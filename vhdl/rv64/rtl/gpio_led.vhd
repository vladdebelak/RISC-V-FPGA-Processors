-- gpio_led.vhd — Memory-mapped 16-bit LED output register
-- Active-high synchronous reset

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpio_led is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        we      : in  std_logic;
        wdata   : in  std_logic_vector(15 downto 0);
        rdata   : out std_logic_vector(15 downto 0);
        led_out : out std_logic_vector(15 downto 0)
    );
end entity gpio_led;

architecture rtl of gpio_led is
    signal led_reg : std_logic_vector(15 downto 0);
begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                led_reg <= x"0000";
            elsif we = '1' then
                led_reg <= wdata;
            end if;
        end if;
    end process;

    rdata   <= led_reg;
    led_out <= led_reg;

end architecture rtl;
