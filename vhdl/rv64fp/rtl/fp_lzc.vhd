library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_lzc is
    port (
        data  : in  std_logic_vector(63 downto 0);
        count : out std_logic_vector(6 downto 0);
        zero  : out std_logic
    );
end entity fp_lzc;

architecture rtl of fp_lzc is
    type lzc_array_t is array (0 to 7) of unsigned(3 downto 0);
    signal lzc_byte     : lzc_array_t;
    signal byte_nonzero : std_logic_vector(7 downto 0);
begin

    zero <= '1' when data = (data'range => '0') else '0';

    process(all)
        variable byte_slice : std_logic_vector(7 downto 0);
    begin
        -- Stage 1: compute LZC within each 8-bit group
        for i in 0 to 7 loop
            byte_slice := data((7-i)*8+7 downto (7-i)*8);
            if unsigned(byte_slice) /= 0 then
                byte_nonzero(i) <= '1';
            else
                byte_nonzero(i) <= '0';
            end if;

            -- Default
            lzc_byte(i) <= to_unsigned(8, 4);

            if    byte_slice(7) = '1' then lzc_byte(i) <= to_unsigned(0, 4);
            elsif byte_slice(6) = '1' then lzc_byte(i) <= to_unsigned(1, 4);
            elsif byte_slice(5) = '1' then lzc_byte(i) <= to_unsigned(2, 4);
            elsif byte_slice(4) = '1' then lzc_byte(i) <= to_unsigned(3, 4);
            elsif byte_slice(3) = '1' then lzc_byte(i) <= to_unsigned(4, 4);
            elsif byte_slice(2) = '1' then lzc_byte(i) <= to_unsigned(5, 4);
            elsif byte_slice(1) = '1' then lzc_byte(i) <= to_unsigned(6, 4);
            elsif byte_slice(0) = '1' then lzc_byte(i) <= to_unsigned(7, 4);
            end if;
        end loop;
    end process;

    -- Stage 2: select first non-zero byte, compose final count
    process(all)
    begin
        count <= std_logic_vector(to_unsigned(64, 7));
        if byte_nonzero(0) = '1' then
            count <= std_logic_vector(to_unsigned(0, 7) + resize(lzc_byte(0), 7));
        elsif byte_nonzero(1) = '1' then
            count <= std_logic_vector(to_unsigned(8, 7) + resize(lzc_byte(1), 7));
        elsif byte_nonzero(2) = '1' then
            count <= std_logic_vector(to_unsigned(16, 7) + resize(lzc_byte(2), 7));
        elsif byte_nonzero(3) = '1' then
            count <= std_logic_vector(to_unsigned(24, 7) + resize(lzc_byte(3), 7));
        elsif byte_nonzero(4) = '1' then
            count <= std_logic_vector(to_unsigned(32, 7) + resize(lzc_byte(4), 7));
        elsif byte_nonzero(5) = '1' then
            count <= std_logic_vector(to_unsigned(40, 7) + resize(lzc_byte(5), 7));
        elsif byte_nonzero(6) = '1' then
            count <= std_logic_vector(to_unsigned(48, 7) + resize(lzc_byte(6), 7));
        elsif byte_nonzero(7) = '1' then
            count <= std_logic_vector(to_unsigned(56, 7) + resize(lzc_byte(7), 7));
        end if;
    end process;

end architecture rtl;
