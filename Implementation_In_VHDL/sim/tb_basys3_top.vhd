library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_basys3_top is
end entity;

architecture sim of tb_basys3_top is

  signal clk     : std_logic := '0';
  signal btnC    : std_logic := '0';
  signal btnR    : std_logic := '0';
  signal sw      : std_logic_vector(15 downto 0) := (others => '0');
  signal led     : std_logic_vector(15 downto 0);
  signal seg     : std_logic_vector(6 downto 0);
  signal dp      : std_logic;
  signal an      : std_logic_vector(3 downto 0);
  signal running : boolean := true;

begin

  clk <= not clk after 5 ns when running else '0';

  dut : entity work.basys3_top
    generic map (
      DEBOUNCE_TIME => 4
    )
    port map (
      clk  => clk,
      btnC => btnC,
      btnR => btnR,
      sw   => sw,
      led  => led,
      seg  => seg,
      dp   => dp,
      an   => an
    );

  process
    variable presses : natural := 0;
  begin
    wait for 10 us;
    assert led(15) = '1' and led(14) = '0' report "free-running test did not pass" severity error;
    if led(15) = '1' and led(14) = '0' then
      report "free-running mode: ALL TESTS PASSED";
    end if;

    sw(15) <= '1';
    btnC   <= '1';
    wait for 200 ns;
    btnC   <= '0';
    while led(15) = '0' and led(14) = '0' and presses < 100 loop
      wait for 300 ns;
      if led(12) = '1' then
        btnR <= '1';
        wait for 200 ns;
        btnR <= '0';
        presses := presses + 1;
      end if;
    end loop;
    wait for 2 us;
    assert led(15) = '1' and led(14) = '0' report "step mode test did not pass" severity error;
    if led(15) = '1' and led(14) = '0' then
      report "step mode: ALL TESTS PASSED after " & integer'image(presses) & " button presses";
    end if;

    running <= false;
    wait;
  end process;

end architecture;
