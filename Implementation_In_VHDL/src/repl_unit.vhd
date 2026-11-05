library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cache_pkg.all;

entity repl_unit is
  generic (
    POLICY : repl_policy_t := LRU
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    set_idx : in  natural range 0 to NUM_SETS-1;
    way     : in  natural range 0 to ASSOC-1;
    touch   : in  std_logic;
    fill    : in  std_logic;
    victim  : out natural range 0 to ASSOC-1
  );
end entity;

architecture rtl of repl_unit is

  type age_set_t is array (0 to ASSOC-1) of natural range 0 to ASSOC-1;
  type age_arr_t is array (0 to NUM_SETS-1) of age_set_t;
  type ptr_arr_t is array (0 to NUM_SETS-1) of natural range 0 to ASSOC-1;

  function init_ages return age_arr_t is
    variable r : age_arr_t;
  begin
    for si in 0 to NUM_SETS-1 loop
      for wi in 0 to ASSOC-1 loop
        r(si)(wi) := wi;
      end loop;
    end loop;
    return r;
  end function;

  signal ages : age_arr_t := init_ages;
  signal ptrs : ptr_arr_t := (others => 0);

begin

  lru_g : if POLICY = LRU generate

    process(clk)
      variable old : natural range 0 to ASSOC-1;
    begin
      if rising_edge(clk) then
        if rst = '1' then
          ages <= init_ages;
        elsif touch = '1' or fill = '1' then
          old := ages(set_idx)(way);
          for wi in 0 to ASSOC-1 loop
            if wi = way then
              ages(set_idx)(wi) <= 0;
            elsif ages(set_idx)(wi) < old then
              ages(set_idx)(wi) <= ages(set_idx)(wi) + 1;
            end if;
          end loop;
        end if;
      end if;
    end process;

    process(ages, set_idx)
    begin
      victim <= 0;
      for wi in 0 to ASSOC-1 loop
        if ages(set_idx)(wi) = ASSOC-1 then
          victim <= wi;
        end if;
      end loop;
    end process;

  end generate;

  fifo_g : if POLICY = FIFO generate

    process(clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          ptrs <= (others => 0);
        elsif fill = '1' and way = ptrs(set_idx) then
          ptrs(set_idx) <= (ptrs(set_idx) + 1) mod ASSOC;
        end if;
      end if;
    end process;

    victim <= ptrs(set_idx);

  end generate;

end architecture;
