library ieee;
use ieee.std_logic_1164.all;

entity bus_arbiter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    req   : in  std_logic_vector(1 downto 0);
    done  : in  std_logic;
    grant : out std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of bus_arbiter is

  signal g    : std_logic_vector(1 downto 0) := "00";
  signal last : std_logic := '1';

begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        g    <= "00";
        last <= '1';
      elsif g = "00" then
        if req(0) = '1' and (req(1) = '0' or last = '1') then
          g    <= "01";
          last <= '0';
        elsif req(1) = '1' then
          g    <= "10";
          last <= '1';
        end if;
      elsif done = '1' then
        g <= "00";
      end if;
    end if;
  end process;

  grant <= g;

end architecture;
