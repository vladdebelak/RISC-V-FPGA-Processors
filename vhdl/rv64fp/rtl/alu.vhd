library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port (
        a           : in  std_logic_vector(63 downto 0);
        b           : in  std_logic_vector(63 downto 0);
        alu_op      : in  std_logic_vector(4 downto 0);
        result      : out std_logic_vector(63 downto 0);
        zero        : out std_logic;
        lt_signed   : out std_logic;
        lt_unsigned : out std_logic
    );
end entity alu;

architecture rtl of alu is
    -- ALU operation encodings
    constant OP_ADD   : std_logic_vector(4 downto 0) := "00000";
    constant OP_SUB   : std_logic_vector(4 downto 0) := "00001";
    constant OP_AND   : std_logic_vector(4 downto 0) := "00010";
    constant OP_OR    : std_logic_vector(4 downto 0) := "00011";
    constant OP_XOR   : std_logic_vector(4 downto 0) := "00100";
    constant OP_SLL   : std_logic_vector(4 downto 0) := "00101";
    constant OP_SRL   : std_logic_vector(4 downto 0) := "00110";
    constant OP_SRA   : std_logic_vector(4 downto 0) := "00111";
    constant OP_SLT   : std_logic_vector(4 downto 0) := "01000";
    constant OP_SLTU  : std_logic_vector(4 downto 0) := "01001";
    constant OP_PASSB : std_logic_vector(4 downto 0) := "01010";
    constant OP_ADDW  : std_logic_vector(4 downto 0) := "10000";
    constant OP_SUBW  : std_logic_vector(4 downto 0) := "10001";
    constant OP_SLLW  : std_logic_vector(4 downto 0) := "10101";
    constant OP_SRLW  : std_logic_vector(4 downto 0) := "10110";
    constant OP_SRAW  : std_logic_vector(4 downto 0) := "10111";

    signal lt_s : std_logic;
    signal lt_u : std_logic;
begin

    zero <= '1' when a = b else '0';
    lt_s <= '1' when signed(a) < signed(b) else '0';
    lt_u <= '1' when unsigned(a) < unsigned(b) else '0';
    lt_signed   <= lt_s;
    lt_unsigned <= lt_u;

    process(all)
        variable r32 : std_logic_vector(31 downto 0);
        variable shamt6 : natural;
        variable shamt5 : natural;
    begin
        result <= (others => '0');
        r32    := (others => '0');
        shamt6 := to_integer(unsigned(b(5 downto 0)));
        shamt5 := to_integer(unsigned(b(4 downto 0)));

        case alu_op is
            when OP_ADD =>
                result <= std_logic_vector(unsigned(a) + unsigned(b));
            when OP_SUB =>
                result <= std_logic_vector(unsigned(a) - unsigned(b));
            when OP_AND =>
                result <= a and b;
            when OP_OR =>
                result <= a or b;
            when OP_XOR =>
                result <= a xor b;
            when OP_SLL =>
                result <= std_logic_vector(shift_left(unsigned(a), shamt6));
            when OP_SRL =>
                result <= std_logic_vector(shift_right(unsigned(a), shamt6));
            when OP_SRA =>
                result <= std_logic_vector(shift_right(signed(a), shamt6));
            when OP_SLT =>
                result <= (63 downto 1 => '0') & lt_s;
            when OP_SLTU =>
                result <= (63 downto 1 => '0') & lt_u;
            when OP_PASSB =>
                result <= b;
            when OP_ADDW =>
                r32 := std_logic_vector(unsigned(a(31 downto 0)) + unsigned(b(31 downto 0)));
                result <= (63 downto 32 => r32(31)) & r32;
            when OP_SUBW =>
                r32 := std_logic_vector(unsigned(a(31 downto 0)) - unsigned(b(31 downto 0)));
                result <= (63 downto 32 => r32(31)) & r32;
            when OP_SLLW =>
                r32 := std_logic_vector(shift_left(unsigned(a(31 downto 0)), shamt5));
                result <= (63 downto 32 => r32(31)) & r32;
            when OP_SRLW =>
                r32 := std_logic_vector(shift_right(unsigned(a(31 downto 0)), shamt5));
                result <= (63 downto 32 => r32(31)) & r32;
            when OP_SRAW =>
                r32 := std_logic_vector(shift_right(signed(a(31 downto 0)), shamt5));
                result <= (63 downto 32 => r32(31)) & r32;
            when others =>
                result <= (others => '0');
        end case;
    end process;

end architecture rtl;
