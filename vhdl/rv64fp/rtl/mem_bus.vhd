library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mem_bus is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        addr        : in  std_logic_vector(63 downto 0);
        wdata       : in  std_logic_vector(63 downto 0);
        we          : in  std_logic;
        re          : in  std_logic;
        size        : in  std_logic_vector(1 downto 0);
        is_unsigned : in  std_logic;
        dm_addr     : out std_logic_vector(8 downto 0);
        dm_wdata    : out std_logic_vector(63 downto 0);
        dm_rdata    : in  std_logic_vector(63 downto 0);
        dm_we       : out std_logic;
        dm_byte_en  : out std_logic_vector(7 downto 0);
        gpio_we     : out std_logic;
        gpio_wdata  : out std_logic_vector(15 downto 0);
        gpio_rdata  : in  std_logic_vector(15 downto 0);
        rdata       : out std_logic_vector(63 downto 0)
    );
end entity mem_bus;

architecture rtl of mem_bus is
    signal sel_gpio : std_logic;
    signal sel_dmem : std_logic;
    signal byte_en_r : std_logic_vector(7 downto 0);
    signal wdata_aligned : std_logic_vector(63 downto 0);
    signal latched_addr     : std_logic_vector(2 downto 0);
    signal latched_size     : std_logic_vector(1 downto 0);
    signal latched_unsigned : std_logic;
    signal latched_sel_gpio : std_logic;
    signal shifted_data     : std_logic_vector(63 downto 0);
    signal extended_data    : std_logic_vector(63 downto 0);
begin

    sel_gpio <= '1' when addr(15 downto 8) = x"FF" else '0';
    sel_dmem <= '1' when addr(15 downto 12) = x"1" else '0';

    dm_addr  <= addr(11 downto 3);
    dm_we    <= we and sel_dmem;
    gpio_we  <= we and sel_gpio;
    gpio_wdata <= wdata(15 downto 0);

    -- Byte-enable generation
    process(all)
        variable shift_amt : natural;
    begin
        byte_en_r <= x"00";
        case size is
            when "00" =>
                byte_en_r <= std_logic_vector(shift_left(unsigned'(x"01"), to_integer(unsigned(addr(2 downto 0)))));
            when "01" =>
                shift_amt := to_integer(unsigned(addr(2 downto 1))) * 2;
                byte_en_r <= std_logic_vector(shift_left(unsigned'(x"03"), shift_amt));
            when "10" =>
                if addr(2) = '1' then byte_en_r <= x"F0"; else byte_en_r <= x"0F"; end if;
            when "11" =>
                byte_en_r <= x"FF";
            when others =>
                byte_en_r <= x"00";
        end case;
    end process;
    dm_byte_en <= byte_en_r;

    -- Write data alignment
    process(all)
    begin
        wdata_aligned <= (others => '0');
        case size is
            when "00" =>
                for i in 0 to 7 loop
                    wdata_aligned(i*8+7 downto i*8) <= wdata(7 downto 0);
                end loop;
            when "01" =>
                for i in 0 to 3 loop
                    wdata_aligned(i*16+15 downto i*16) <= wdata(15 downto 0);
                end loop;
            when "10" =>
                wdata_aligned <= wdata(31 downto 0) & wdata(31 downto 0);
            when "11" =>
                wdata_aligned <= wdata;
            when others =>
                wdata_aligned <= (others => '0');
        end case;
    end process;
    dm_wdata <= wdata_aligned;

    -- Latched control signals
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                latched_addr     <= (others => '0');
                latched_size     <= (others => '0');
                latched_unsigned <= '0';
                latched_sel_gpio <= '0';
            elsif re = '1' or we = '1' then
                latched_addr     <= addr(2 downto 0);
                latched_size     <= size;
                latched_unsigned <= is_unsigned;
                latched_sel_gpio <= sel_gpio;
            end if;
        end if;
    end process;

    -- Load data extraction and sign/zero extension
    process(all)
        variable shift_bits : natural;
    begin
        shift_bits := to_integer(unsigned(latched_addr)) * 8;
        shifted_data <= std_logic_vector(shift_right(unsigned(dm_rdata), shift_bits));

        extended_data <= (others => '0');
        case latched_size is
            when "00" =>
                if latched_unsigned = '1' then
                    extended_data <= (63 downto 8 => '0') & shifted_data(7 downto 0);
                else
                    extended_data <= (63 downto 8 => shifted_data(7)) & shifted_data(7 downto 0);
                end if;
            when "01" =>
                if latched_unsigned = '1' then
                    extended_data <= (63 downto 16 => '0') & shifted_data(15 downto 0);
                else
                    extended_data <= (63 downto 16 => shifted_data(15)) & shifted_data(15 downto 0);
                end if;
            when "10" =>
                if latched_unsigned = '1' then
                    extended_data <= (63 downto 32 => '0') & shifted_data(31 downto 0);
                else
                    extended_data <= (63 downto 32 => shifted_data(31)) & shifted_data(31 downto 0);
                end if;
            when "11" =>
                extended_data <= shifted_data;
            when others =>
                extended_data <= (others => '0');
        end case;
    end process;

    -- Read data mux
    process(all)
    begin
        if latched_sel_gpio = '1' then
            rdata <= (63 downto 16 => '0') & gpio_rdata;
        else
            rdata <= extended_data;
        end if;
    end process;

end architecture rtl;
