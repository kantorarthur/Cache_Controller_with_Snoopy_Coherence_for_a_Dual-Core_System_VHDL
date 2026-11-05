library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cache_pkg is

  constant ADDR_W      : positive := 32;
  constant WORD_W      : positive := 32;
  constant OFFSET_W    : positive := 4;
  constant INDEX_W     : positive := 2;
  constant WAY_W       : positive := 1;
  constant MEM_LINES_W : positive := 8;
  constant MEM_LATENCY : positive := 4;

  constant LINE_SIZE      : positive := 2**OFFSET_W;
  constant NUM_SETS       : positive := 2**INDEX_W;
  constant ASSOC          : positive := 2**WAY_W;
  constant TAG_W          : positive := ADDR_W - INDEX_W - OFFSET_W;
  constant WORDS_PER_LINE : positive := LINE_SIZE / 4;
  constant LINE_W         : positive := 8 * LINE_SIZE;

  type msi_t         is (I, S, M);
  type bus_cmd_t     is (B_IDLE, B_RD, B_RDX, B_UPGR, B_FLUSH);
  type repl_policy_t is (LRU, FIFO);

  subtype addr_t      is std_logic_vector(ADDR_W-1 downto 0);
  subtype word_t      is std_logic_vector(WORD_W-1 downto 0);
  subtype tag_t       is std_logic_vector(TAG_W-1 downto 0);
  subtype line_data_t is std_logic_vector(LINE_W-1 downto 0);

  type cache_line_t is record
    state : msi_t;
    tag   : tag_t;
    data  : line_data_t;
  end record;

  type cache_set_t   is array (0 to ASSOC-1) of cache_line_t;
  type cache_array_t is array (0 to NUM_SETS-1) of cache_set_t;

  constant EMPTY_LINE : cache_line_t := (state => I, tag => (others => '0'), data => (others => '0'));

  function get_tag   (a : addr_t) return tag_t;
  function get_index (a : addr_t) return natural;
  function get_word  (a : addr_t) return natural;
  function line_addr (a : addr_t) return addr_t;
  function make_addr (t : tag_t; idx : natural) return addr_t;
  function find_way  (st : cache_set_t; t : tag_t) return integer;
  function find_free (st : cache_set_t) return integer;

end package;

package body cache_pkg is

  function get_tag (a : addr_t) return tag_t is
  begin
    return a(ADDR_W-1 downto ADDR_W-TAG_W);
  end function;

  function get_index (a : addr_t) return natural is
  begin
    return to_integer(unsigned(a(INDEX_W+OFFSET_W-1 downto OFFSET_W)));
  end function;

  function get_word (a : addr_t) return natural is
  begin
    return to_integer(unsigned(a(OFFSET_W-1 downto 2)));
  end function;

  function line_addr (a : addr_t) return addr_t is
    variable r : addr_t := a;
  begin
    r(OFFSET_W-1 downto 0) := (others => '0');
    return r;
  end function;

  function make_addr (t : tag_t; idx : natural) return addr_t is
    variable r : addr_t := (others => '0');
  begin
    r(ADDR_W-1 downto ADDR_W-TAG_W) := t;
    r(INDEX_W+OFFSET_W-1 downto OFFSET_W) := std_logic_vector(to_unsigned(idx, INDEX_W));
    return r;
  end function;

  function find_way (st : cache_set_t; t : tag_t) return integer is
  begin
    for wi in 0 to ASSOC-1 loop
      if st(wi).state /= I and st(wi).tag = t then
        return wi;
      end if;
    end loop;
    return -1;
  end function;

  function find_free (st : cache_set_t) return integer is
  begin
    for wi in 0 to ASSOC-1 loop
      if st(wi).state = I then
        return wi;
      end if;
    end loop;
    return -1;
  end function;

end package body;
