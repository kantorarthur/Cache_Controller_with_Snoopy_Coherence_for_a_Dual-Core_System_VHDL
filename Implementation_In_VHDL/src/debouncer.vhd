library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debouncer is
  generic (
    STABLE_CYCLES : positive := 1_000_000
  );
  port (
    clk   : in  std_logic;
    btn   : in  std_logic;
    pulse : out std_logic
  );
end entity;

architecture rtl of debouncer is

  signal sync0, sync1 : std_logic := '0';
  signal stable       : std_logic := '0';
  signal stable_prev  : std_logic := '0';
  signal count        : natural range 0 to STABLE_CYCLES := 0;

begin

  process(clk)
  begin
    if rising_edge(clk) then
      sync0 <= btn;
      sync1 <= sync0;

      if sync1 = stable then
        count <= 0;
      elsif count = STABLE_CYCLES then
        stable <= sync1;
        count  <= 0;
      else
        count <= count + 1;
      end if;

      stable_prev <= stable;
    end if;
  end process;

  pulse <= stable and not stable_prev;

end architecture;
