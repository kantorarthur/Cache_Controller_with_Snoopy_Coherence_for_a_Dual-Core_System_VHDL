library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cache_pkg.all;

entity cache_controller is
  generic (
    POLICY : repl_policy_t := LRU
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    cpu_req     : in  std_logic;
    cpu_we      : in  std_logic;
    cpu_addr    : in  addr_t;
    cpu_wdata   : in  word_t;
    cpu_rdata   : out word_t;
    cpu_ready   : out std_logic;
    bus_req     : out std_logic;
    bus_grant   : in  std_logic;
    cmd_o       : out bus_cmd_t;
    addr_o      : out addr_t;
    data_o      : out line_data_t;
    flush_o     : out std_logic;
    bus_cmd     : in  bus_cmd_t;
    bus_addr    : in  addr_t;
    bus_data    : in  line_data_t;
    bus_done    : in  std_logic;
    dbg_hit     : out std_logic;
    dbg_miss    : out std_logic;
    probe_addr  : in  addr_t;
    probe_state : out msi_t;
    dbg_cache   : out cache_array_t
  );
end entity;

architecture rtl of cache_controller is

  type proc_state_t  is (IDLE, COMPARE, WRITEBACK, WAIT_GRANT, BUS_TRANS);
  type snoop_state_t is (SNOOP_IDLE, LOOKUP, FLUSH, INVALIDATE);

  signal cache : cache_array_t := (others => (others => EMPTY_LINE));

  signal pst        : proc_state_t := IDLE;
  signal req_we     : std_logic := '0';
  signal req_addr   : addr_t := (others => '0');
  signal req_wdata  : word_t := (others => '0');
  signal pend_cmd   : bus_cmd_t := B_IDLE;
  signal tgt_way    : natural range 0 to ASSOC-1 := 0;
  signal after_fill : std_logic := '0';
  signal ready_r    : std_logic := '0';
  signal rdata_r    : word_t := (others => '0');
  signal hit_r      : std_logic := '0';
  signal miss_r     : std_logic := '0';

  signal sst        : snoop_state_t := SNOOP_IDLE;
  signal sn_addr    : addr_t := (others => '0');
  signal sn_cmd     : bus_cmd_t := B_IDLE;
  signal sn_way     : natural range 0 to ASSOC-1 := 0;
  signal sn_handled : std_logic := '0';

  signal req_idx     : natural range 0 to NUM_SETS-1;
  signal req_tag     : tag_t;
  signal p_way       : integer range -1 to ASSOC-1;
  signal free_way    : integer range -1 to ASSOC-1;
  signal sn_idx      : natural range 0 to NUM_SETS-1;
  signal s_way       : integer range -1 to ASSOC-1;
  signal victim_addr : addr_t;

  signal repl_way    : natural range 0 to ASSOC-1 := 0;
  signal repl_touch  : std_logic := '0';
  signal repl_fill   : std_logic := '0';
  signal repl_victim : natural range 0 to ASSOC-1;

begin

  req_idx     <= get_index(req_addr);
  req_tag     <= get_tag(req_addr);
  p_way       <= find_way(cache(req_idx), req_tag);
  free_way    <= find_free(cache(req_idx));
  sn_idx      <= get_index(sn_addr);
  s_way       <= find_way(cache(sn_idx), get_tag(sn_addr));
  victim_addr <= make_addr(cache(req_idx)(tgt_way).tag, req_idx);

  repl : entity work.repl_unit
    generic map (
      POLICY => POLICY
    )
    port map (
      clk     => clk,
      rst     => rst,
      set_idx => req_idx,
      way     => repl_way,
      touch   => repl_touch,
      fill    => repl_fill,
      victim  => repl_victim
    );

  process(clk)
    variable w  : natural range 0 to WORDS_PER_LINE-1;
    variable v  : natural range 0 to ASSOC-1;
    variable pw : natural range 0 to ASSOC-1;
  begin
    if rising_edge(clk) then
      ready_r    <= '0';
      hit_r      <= '0';
      miss_r     <= '0';
      repl_touch <= '0';
      repl_fill  <= '0';

      if rst = '1' then
        cache      <= (others => (others => EMPTY_LINE));
        pst        <= IDLE;
        sst        <= SNOOP_IDLE;
        pend_cmd   <= B_IDLE;
        after_fill <= '0';
        sn_handled <= '0';
      else

        case pst is

          when IDLE =>
            after_fill <= '0';
            if cpu_req = '1' and ready_r = '0' then
              req_we    <= cpu_we;
              req_addr  <= cpu_addr;
              req_wdata <= cpu_wdata;
              pst       <= COMPARE;
            end if;

          when COMPARE =>
            if sst = SNOOP_IDLE then
              w := get_word(req_addr);
              if p_way >= 0 then
                pw := p_way;
                if after_fill = '0' then
                  hit_r <= '1';
                end if;
                if req_we = '0' then
                  for k in 0 to WORDS_PER_LINE-1 loop
                    if k = w then
                      rdata_r <= cache(req_idx)(pw).data((k+1)*WORD_W-1 downto k*WORD_W);
                    end if;
                  end loop;
                  repl_way   <= pw;
                  repl_touch <= '1';
                  ready_r    <= '1';
                  pst        <= IDLE;
                elsif cache(req_idx)(pw).state = M then
                  for k in 0 to WORDS_PER_LINE-1 loop
                    if k = w then
                      cache(req_idx)(pw).data((k+1)*WORD_W-1 downto k*WORD_W) <= req_wdata;
                    end if;
                  end loop;
                  repl_way   <= pw;
                  repl_touch <= '1';
                  ready_r    <= '1';
                  pst        <= IDLE;
                else
                  tgt_way  <= pw;
                  pend_cmd <= B_UPGR;
                  pst      <= WAIT_GRANT;
                end if;
              else
                miss_r <= '1';
                if free_way >= 0 then
                  v := free_way;
                else
                  v := repl_victim;
                end if;
                tgt_way <= v;
                if cache(req_idx)(v).state = M then
                  pst <= WRITEBACK;
                else
                  if req_we = '1' then
                    pend_cmd <= B_RDX;
                  else
                    pend_cmd <= B_RD;
                  end if;
                  pst <= WAIT_GRANT;
                end if;
              end if;
            end if;

          when WRITEBACK =>
            if bus_grant = '0' and cache(req_idx)(tgt_way).state /= M then
              if req_we = '1' then
                pend_cmd <= B_RDX;
              else
                pend_cmd <= B_RD;
              end if;
              pst <= WAIT_GRANT;
            elsif bus_grant = '1' and bus_done = '1' then
              cache(req_idx)(tgt_way).state <= I;
              if req_we = '1' then
                pend_cmd <= B_RDX;
              else
                pend_cmd <= B_RD;
              end if;
              pst <= WAIT_GRANT;
            end if;

          when WAIT_GRANT =>
            if pend_cmd = B_UPGR and cache(req_idx)(tgt_way).state /= S then
              pend_cmd <= B_RDX;
            end if;
            if bus_grant = '1' then
              pst <= BUS_TRANS;
            end if;

          when BUS_TRANS =>
            if bus_done = '1' then
              if pend_cmd = B_UPGR then
                cache(req_idx)(tgt_way).state <= M;
              else
                cache(req_idx)(tgt_way).tag  <= req_tag;
                cache(req_idx)(tgt_way).data <= bus_data;
                if pend_cmd = B_RDX then
                  cache(req_idx)(tgt_way).state <= M;
                else
                  cache(req_idx)(tgt_way).state <= S;
                end if;
                repl_way  <= tgt_way;
                repl_fill <= '1';
              end if;
              after_fill <= '1';
              pend_cmd   <= B_IDLE;
              pst        <= COMPARE;
            end if;

        end case;

        case sst is

          when SNOOP_IDLE =>
            if bus_done = '1' then
              sn_handled <= '0';
            elsif bus_grant = '0' and sn_handled = '0' and
                  (bus_cmd = B_RD or bus_cmd = B_RDX or bus_cmd = B_UPGR) then
              sn_addr <= bus_addr;
              sn_cmd  <= bus_cmd;
              sst     <= LOOKUP;
            end if;

          when LOOKUP =>
            if s_way >= 0 and cache(sn_idx)(s_way).state = M and
               (sn_cmd = B_RD or sn_cmd = B_RDX) then
              sn_way <= s_way;
              sst    <= FLUSH;
            elsif s_way >= 0 and cache(sn_idx)(s_way).state = S and
                  (sn_cmd = B_RDX or sn_cmd = B_UPGR) then
              sn_way <= s_way;
              sst    <= INVALIDATE;
            else
              sn_handled <= not bus_done;
              sst        <= SNOOP_IDLE;
            end if;

          when FLUSH =>
            if bus_done = '1' then
              if sn_cmd = B_RD then
                cache(sn_idx)(sn_way).state <= S;
              else
                cache(sn_idx)(sn_way).state <= I;
              end if;
              sn_handled <= '0';
              sst        <= SNOOP_IDLE;
            end if;

          when INVALIDATE =>
            cache(sn_idx)(sn_way).state <= I;
            sn_handled <= not bus_done;
            sst        <= SNOOP_IDLE;

        end case;

      end if;
    end if;
  end process;

  process(probe_addr, cache)
    variable wy : integer range -1 to ASSOC-1;
  begin
    wy := find_way(cache(get_index(probe_addr)), get_tag(probe_addr));
    if wy < 0 then
      probe_state <= I;
    else
      probe_state <= cache(get_index(probe_addr))(wy).state;
    end if;
  end process;

  bus_req <= '1' when pst = WRITEBACK or pst = WAIT_GRANT or pst = BUS_TRANS else '0';

  cmd_o <= B_FLUSH  when pst = WRITEBACK else
           pend_cmd when pst = WAIT_GRANT or pst = BUS_TRANS else
           B_IDLE;

  addr_o <= victim_addr when pst = WRITEBACK else line_addr(req_addr);

  data_o <= cache(sn_idx)(sn_way).data when sst = FLUSH else cache(req_idx)(tgt_way).data;

  flush_o <= '1' when sst = FLUSH else '0';

  cpu_rdata <= rdata_r;
  cpu_ready <= ready_r;
  dbg_hit   <= hit_r;
  dbg_miss  <= miss_r;
  dbg_cache <= cache;

end architecture;
