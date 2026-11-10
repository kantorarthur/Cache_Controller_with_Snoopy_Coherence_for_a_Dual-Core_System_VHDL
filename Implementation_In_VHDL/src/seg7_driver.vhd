library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_driver is
  port (
    clk    : in  std_logic;
    digit3 : in  std_logic_vector(6 downto 0);
    digit2 : in  std_logic_vector(6 downto 0);
    digit1 : in  std_logic_vector(6 downto 0);
    digit0 : in  std_logic_vector(6 downto 0);
    seg    : out std_logic_vector(6 downto 0);
    an     : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of seg7_driver is

  signal refresh : unsigned(18 downto 0) := (others => '0');

begin

  process(clk)
  begin
    if rising_edge(clk) then
      refresh <= refresh + 1;
    end if;
  end process;

  process(refresh, digit3, digit2, digit1, digit0)
  begin
    case refresh(18 downto 17) is
      when "00" =>
        an  <= "1110";
        seg <= not digit0;
      when "01" =>
        an  <= "1101";
        seg <= not digit1;
      when "10" =>
        an  <= "1011";
        seg <= not digit2;
      when others =>
        an  <= "0111";
        seg <= not digit3;
    end case;
  end process;

end architecture;
