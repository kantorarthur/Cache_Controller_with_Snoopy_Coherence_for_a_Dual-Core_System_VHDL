library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cache_pkg.all;

entity main_memory is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    bus_cmd     : in  bus_cmd_t;
    bus_addr    : in  addr_t;
    bus_data    : in  line_data_t;
    snoop_flush : in  std_logic;
    rdata       : out line_data_t;
    done        : out std_logic
  );
end entity;

architecture beh of main_memory is

  constant MEM_LINES : positive := 2**MEM_LINES_W;

  type mem_t    is array (0 to MEM_LINES-1) of line_data_t;
  type mstate_t is (M_IDLE, M_BUSY, M_DONE);

  function init_mem return mem_t is
    variable r : mem_t;
  begin
    for li in 0 to MEM_LINES-1 loop
      for wi in 0 to WORDS_PER_LINE-1 loop
        r(li)((wi+1)*WORD_W-1 downto wi*WORD_W) := std_logic_vector(to_unsigned(li*LINE_SIZE + 4*wi, WORD_W));
      end loop;
    end loop;
    return r;
  end function;

  function line_no (a : addr_t) return natural is
  begin
    return to_integer(unsigned(a(MEM_LINES_W+OFFSET_W-1 downto OFFSET_W)));
  end function;

  signal mem     : mem_t := init_mem;
  signal st      : mstate_t := M_IDLE;
  signal cnt     : natural range 0 to MEM_LATENCY := 0;
  signal rdata_r : line_data_t := (others => '0');
  signal done_r  : std_logic := '0';

begin

  assert MEM_LATENCY >= 4 report "MEM_LATENCY must be at least 4" severity failure;

  process(clk)
    variable ln : natural range 0 to MEM_LINES-1;
  begin
    if rising_edge(clk) then
      done_r <= '0';
      if rst = '1' then
        st  <= M_IDLE;
        cnt <= 0;
      else
        case st is
          when M_IDLE =>
            if bus_cmd /= B_IDLE then
              cnt <= 1;
              st  <= M_BUSY;
            end if;
          when M_BUSY =>
            if cnt < MEM_LATENCY then
              cnt <= cnt + 1;
            else
              ln := line_no(bus_addr);
              if bus_cmd = B_FLUSH or snoop_flush = '1' then
                mem(ln) <= bus_data;
                rdata_r <= bus_data;
              elsif bus_cmd = B_RD or bus_cmd = B_RDX then
                rdata_r <= mem(ln);
              end if;
              done_r <= '1';
              st     <= M_DONE;
            end if;
          when M_DONE =>
            st <= M_IDLE;
        end case;
      end if;
    end if;
  end process;

  rdata <= rdata_r;
  done  <= done_r;

end architecture;
