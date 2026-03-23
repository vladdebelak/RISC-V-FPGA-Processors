library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_mem is
    port (
        clk     : in  std_logic;
        addr    : in  std_logic_vector(8 downto 0);
        wdata   : in  std_logic_vector(63 downto 0);
        rdata   : out std_logic_vector(63 downto 0);
        we      : in  std_logic;
        byte_en : in  std_logic_vector(7 downto 0)
    );
end entity data_mem;

architecture rtl of data_mem is
    type mem_array_t is array (0 to 511) of std_logic_vector(63 downto 0);
    attribute ram_style : string;
    signal mem : mem_array_t := (others => (others => '0'));
    attribute ram_style of mem : signal is "block";
    signal rdata_r : std_logic_vector(63 downto 0);
begin

    process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            addr_int := to_integer(unsigned(addr));
            for i in 0 to 7 loop
                if we = '1' and byte_en(i) = '1' then
                    mem(addr_int)(i*8+7 downto i*8) <= wdata(i*8+7 downto i*8);
                end if;
            end loop;
            rdata_r <= mem(addr_int);
        end if;
    end process;

    rdata <= rdata_r;

end architecture rtl;
