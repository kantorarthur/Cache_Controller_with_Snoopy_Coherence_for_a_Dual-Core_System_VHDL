library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.cache_pkg.all;

entity tb_dual_core is
end entity;

architecture sim of tb_dual_core is

  constant POLICY : repl_policy_t := LRU;
  constant T      : time := 10 ns;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal running : boolean := true;

  signal req0, we0, ready0 : std_logic := '0';
  signal req1, we1, ready1 : std_logic := '0';
  signal addr0, addr1      : addr_t := (others => '0');
  signal wdata0, wdata1    : word_t := (others => '0');
  signal rdata0, rdata1    : word_t;
  signal probe0, probe1    : addr_t := (others => '0');
  signal pstate0, pstate1  : msi_t;
  signal dbg_hit, dbg_miss : std_logic_vector(1 downto 0);
  signal hits0, misses0    : natural := 0;

  signal cache0, cache1    : cache_array_t;
  signal mon_cmd           : bus_cmd_t;
  signal mon_addr          : addr_t;
  signal mon_data          : line_data_t;
  signal mon_done          : std_logic;
  signal mon_grant         : std_logic_vector(1 downto 0);
  signal mon_flush         : std_logic_vector(1 downto 0);
  signal scenario          : natural := 0;
  signal finished          : std_logic := '0';
  signal err_count         : natural := 0;

  type op_rec_t is record
    active : boolean;
    we     : std_logic;
    addr   : addr_t;
    wdata  : word_t;
    miss   : boolean;
  end record;
  type op_arr_t is array (0 to 1) of op_rec_t;

  function scenario_name (n : natural) return string is
  begin
    case n is
      when 1      => return "1. Hit and miss";
      when 2      => return "2. Replacement";
      when 3      => return "3. Write-back";
      when 4      => return "4. Both cores read the same line";
      when 5      => return "5. Write to a shared line invalidates the other copy";
      when 6      => return "6. Read of a line modified in the other cache";
      when 7      => return "7. Simultaneous writes to the same shared line";
      when others => return "";
    end case;
  end function;

  function hexv (v : std_logic_vector) return string is
    constant digits : string(1 to 16) := "0123456789ABCDEF";
    constant n      : natural := v'length / 4;
    variable x      : std_logic_vector(v'length-1 downto 0) := v;
    variable r      : string(1 to n);
  begin
    for k in 0 to n-1 loop
      if is_x(x(v'length-1-4*k downto v'length-4-4*k)) then
        r(k+1) := 'X';
      else
        r(k+1) := digits(to_integer(unsigned(x(v'length-1-4*k downto v'length-4-4*k))) + 1);
      end if;
    end loop;
    return r;
  end function;

  function msi_str (st : msi_t) return string is
  begin
    case st is
      when M => return "M";
      when S => return "S";
      when I => return "I";
    end case;
  end function;

  function cmd_str (c : bus_cmd_t) return string is
  begin
    case c is
      when B_RD    => return "BusRd";
      when B_RDX   => return "BusRdX";
      when B_UPGR  => return "BusUpgr";
      when B_FLUSH => return "Flush";
      when B_IDLE  => return "Idle";
    end case;
  end function;

begin

  clk <= not clk after T/2 when running else '0';

  dut : entity work.dual_core_system
    generic map (
      POLICY => POLICY
    )
    port map (
      clk          => clk,
      rst          => rst,
      cpu0_req     => req0,
      cpu0_we      => we0,
      cpu0_addr    => addr0,
      cpu0_wdata   => wdata0,
      cpu0_rdata   => rdata0,
      cpu0_ready   => ready0,
      cpu1_req     => req1,
      cpu1_we      => we1,
      cpu1_addr    => addr1,
      cpu1_wdata   => wdata1,
      cpu1_rdata   => rdata1,
      cpu1_ready   => ready1,
      dbg_hit      => dbg_hit,
      dbg_miss     => dbg_miss,
      probe0_addr  => probe0,
      probe0_state => pstate0,
      probe1_addr  => probe1,
      probe1_state => pstate1,
      dbg_cache0   => cache0,
      dbg_cache1   => cache1,
      mon_cmd      => mon_cmd,
      mon_addr     => mon_addr,
      mon_data     => mon_data,
      mon_done     => mon_done,
      mon_grant    => mon_grant,
      mon_flush    => mon_flush
    );

  logger : process(clk)

    file log_f : text open write_mode is "cache_log.jsonl";

    variable l        : line;
    variable ops      : op_arr_t := (others => (false, '0', (others => '0'), (others => '0'), false));
    variable in_txn   : boolean := false;
    variable txn_core : natural := 0;
    variable prev0    : cache_array_t := (others => (others => EMPTY_LINE));
    variable prev1    : cache_array_t := (others => (others => EMPTY_LINE));
    variable last_sc  : natural := 0;
    variable ended    : boolean := false;
    variable cfg_done : boolean := false;
    variable rq, rdy  : std_logic;
    variable c_we     : std_logic;
    variable c_addr   : addr_t;
    variable c_wdata  : word_t;
    variable c_rdata  : word_t;

    procedure put_t (kind : string) is
    begin
      write(l, string'("{""t"":") & integer'image(now / 1 ns) & ",""type"":""" & kind & """");
    end procedure;

    procedure put_cache (name : string; c : cache_array_t) is
    begin
      write(l, string'(",""" & name & """:["));
      for si in 0 to NUM_SETS-1 loop
        if si > 0 then
          write(l, string'(","));
        end if;
        write(l, string'("["));
        for wi in 0 to ASSOC-1 loop
          if wi > 0 then
            write(l, string'(","));
          end if;
          write(l, string'("{""state"":""") & msi_str(c(si)(wi).state) &
                   """,""addr"":""" & hexv(make_addr(c(si)(wi).tag, si)) & """,""data"":[");
          for k in 0 to WORDS_PER_LINE-1 loop
            if k > 0 then
              write(l, string'(","));
            end if;
            write(l, string'("""") & hexv(c(si)(wi).data((k+1)*WORD_W-1 downto k*WORD_W)) & """");
          end loop;
          write(l, string'("]}"));
        end loop;
        write(l, string'("]"));
      end loop;
      write(l, string'("]"));
    end procedure;

  begin
    if rising_edge(clk) and rst = '0' then

      if not cfg_done then
        put_t("config");
        write(l, string'(",""sets"":") & integer'image(NUM_SETS) &
                 ",""ways"":" & integer'image(ASSOC) &
                 ",""line_size"":" & integer'image(LINE_SIZE) & ",""policy"":""");
        if POLICY = LRU then
          write(l, string'("LRU""}"));
        else
          write(l, string'("FIFO""}"));
        end if;
        writeline(log_f, l);
        cfg_done := true;
      end if;

      for c in 0 to 1 loop
        if c = 0 then
          rq := req0; rdy := ready0; c_we := we0; c_addr := addr0; c_wdata := wdata0; c_rdata := rdata0;
        else
          rq := req1; rdy := ready1; c_we := we1; c_addr := addr1; c_wdata := wdata1; c_rdata := rdata1;
        end if;
        if dbg_miss(c) = '1' and ops(c).active then
          ops(c).miss := true;
        end if;
        if rdy = '1' and ops(c).active then
          put_t("cpu");
          write(l, string'(",""core"":") & integer'image(c) & ",""op"":""");
          if ops(c).we = '1' then
            write(l, string'("W"",""value"":""") & hexv(ops(c).wdata) & """");
          else
            write(l, string'("R"",""value"":""") & hexv(c_rdata) & """");
          end if;
          write(l, string'(",""addr"":""") & hexv(ops(c).addr) & """,""result"":""");
          if ops(c).miss then
            write(l, string'("miss""}"));
          else
            write(l, string'("hit""}"));
          end if;
          writeline(log_f, l);
          ops(c).active := false;
        end if;
        if rq = '1' and not ops(c).active then
          ops(c) := (true, c_we, c_addr, c_wdata, false);
        end if;
      end loop;

      if scenario /= 0 and scenario /= last_sc then
        put_t("scenario");
        write(l, string'(",""id"":") & integer'image(scenario) &
                 ",""name"":""" & scenario_name(scenario) & """}");
        writeline(log_f, l);
        last_sc := scenario;
      end if;

      if not in_txn and mon_cmd /= B_IDLE then
        if mon_grant(1) = '1' then
          txn_core := 1;
        else
          txn_core := 0;
        end if;
        put_t("bus_start");
        write(l, string'(",""core"":") & integer'image(txn_core) &
                 ",""cmd"":""" & cmd_str(mon_cmd) & """,""addr"":""" & hexv(mon_addr) & """}");
        writeline(log_f, l);
        in_txn := true;
      end if;

      if in_txn and mon_done = '1' then
        put_t("bus_end");
        write(l, string'(",""core"":") & integer'image(txn_core) &
                 ",""cmd"":""" & cmd_str(mon_cmd) & """,""addr"":""" & hexv(mon_addr) & """,""source"":""");
        if mon_flush(0) = '1' then
          write(l, string'("cache0"""));
        elsif mon_flush(1) = '1' then
          write(l, string'("cache1"""));
        elsif mon_cmd = B_FLUSH then
          write(l, string'("cache") & integer'image(txn_core) & """");
        elsif mon_cmd = B_UPGR then
          write(l, string'("none"""));
        else
          write(l, string'("memory"""));
        end if;
        if mon_cmd = B_FLUSH or mon_flush /= "00" then
          write(l, string'(",""mem_write"":true"));
        else
          write(l, string'(",""mem_write"":false"));
        end if;
        if mon_cmd = B_UPGR then
          write(l, string'(",""data"":[]}"));
        else
          write(l, string'(",""data"":["));
          for k in 0 to WORDS_PER_LINE-1 loop
            if k > 0 then
              write(l, string'(","));
            end if;
            write(l, string'("""") & hexv(mon_data((k+1)*WORD_W-1 downto k*WORD_W)) & """");
          end loop;
          write(l, string'("]}"));
        end if;
        writeline(log_f, l);
        in_txn := false;
      end if;

      if cache0 /= prev0 or cache1 /= prev1 then
        put_t("state");
        put_cache("cache0", cache0);
        put_cache("cache1", cache1);
        write(l, string'("}"));
        writeline(log_f, l);
        prev0 := cache0;
        prev1 := cache1;
      end if;

      if finished = '1' and not ended then
        put_t("end");
        write(l, string'(",""errors"":") & integer'image(err_count) & "}");
        writeline(log_f, l);
        ended := true;
      end if;

    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if dbg_hit(0) = '1' then
        hits0 <= hits0 + 1;
      end if;
      if dbg_miss(0) = '1' then
        misses0 <= misses0 + 1;
      end if;
    end if;
  end process;

  stim : process

    variable errors : natural := 0;

    function ad (a : natural) return addr_t is
    begin
      return std_logic_vector(to_unsigned(a, ADDR_W));
    end function;

    function wv (a : natural) return word_t is
    begin
      return std_logic_vector(to_unsigned(a, WORD_W));
    end function;

    function hex (v : word_t) return string is
      constant digits : string(1 to 16) := "0123456789ABCDEF";
      variable r      : string(1 to 8);
    begin
      for k in 0 to 7 loop
        if is_x(v(31-4*k downto 28-4*k)) then
          r(k+1) := 'X';
        else
          r(k+1) := digits(to_integer(unsigned(v(31-4*k downto 28-4*k))) + 1);
        end if;
      end loop;
      return r;
    end function;

    procedure cpu_op (core : natural; we : std_logic; a : natural; d : word_t; r : out word_t) is
    begin
      if core = 0 then
        req0 <= '1'; we0 <= we; addr0 <= ad(a); wdata0 <= d;
      else
        req1 <= '1'; we1 <= we; addr1 <= ad(a); wdata1 <= d;
      end if;
      loop
        wait until rising_edge(clk);
        wait for 1 ns;
        exit when (core = 0 and ready0 = '1') or (core = 1 and ready1 = '1');
      end loop;
      if core = 0 then
        r := rdata0; req0 <= '0';
      else
        r := rdata1; req1 <= '0';
      end if;
    end procedure;

    procedure rd (core : natural; a : natural; expected : word_t) is
      variable r : word_t;
    begin
      cpu_op(core, '0', a, (others => '0'), r);
      if r /= expected then
        report "core " & integer'image(core) & " read @" & integer'image(a) &
               " = " & hex(r) & ", expected " & hex(expected) severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure wr (core : natural; a : natural; d : word_t) is
      variable r : word_t;
    begin
      cpu_op(core, '1', a, d, r);
    end procedure;

    procedure wr_both (a0 : natural; d0 : word_t; a1 : natural; d1 : word_t) is
      variable f0 : boolean := false;
      variable f1 : boolean := false;
    begin
      req0 <= '1'; we0 <= '1'; addr0 <= ad(a0); wdata0 <= d0;
      req1 <= '1'; we1 <= '1'; addr1 <= ad(a1); wdata1 <= d1;
      while not (f0 and f1) loop
        wait until rising_edge(clk);
        wait for 1 ns;
        if ready0 = '1' and not f0 then
          f0 := true; req0 <= '0';
        end if;
        if ready1 = '1' and not f1 then
          f1 := true; req1 <= '0';
        end if;
      end loop;
    end procedure;

    procedure chk_state (core : natural; a : natural; expected : msi_t) is
      variable got : msi_t;
    begin
      if core = 0 then
        probe0 <= ad(a);
      else
        probe1 <= ad(a);
      end if;
      wait for 1 ns;
      if core = 0 then
        got := pstate0;
      else
        got := pstate1;
      end if;
      if got /= expected then
        report "core " & integer'image(core) & " line @" & integer'image(a) &
               " in state " & msi_t'image(got) & ", expected " & msi_t'image(expected) severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure chk_count (name : string; got : natural; expected : natural) is
    begin
      if got /= expected then
        report name & " = " & integer'image(got) & ", expected " & integer'image(expected) severity error;
        errors := errors + 1;
      end if;
    end procedure;

  begin

    rst <= '1';
    wait for 3*T;
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;

    scenario <= 1;
    report "1. hit and miss";
    rd(0, 16#000#, wv(16#000#));
    rd(0, 16#004#, wv(16#004#));
    wait until rising_edge(clk);
    wait for 1 ns;
    chk_count("core 0 misses", misses0, 1);
    chk_count("core 0 hits", hits0, 1);

    scenario <= 2;
    report "2. replacement";
    rd(0, 16#040#, wv(16#040#));
    rd(0, 16#000#, wv(16#000#));
    rd(0, 16#080#, wv(16#080#));
    if POLICY = LRU then
      chk_state(0, 16#000#, S);
      chk_state(0, 16#040#, I);
    else
      chk_state(0, 16#000#, I);
      chk_state(0, 16#040#, S);
    end if;
    chk_state(0, 16#080#, S);

    scenario <= 3;
    report "3. write-back";
    wr(0, 16#010#, x"AAAA0001");
    chk_state(0, 16#010#, M);
    rd(0, 16#050#, wv(16#050#));
    rd(0, 16#090#, wv(16#090#));
    chk_state(0, 16#010#, I);
    rd(1, 16#010#, x"AAAA0001");

    scenario <= 4;
    report "4. both cores read the same line";
    rd(0, 16#020#, wv(16#020#));
    rd(1, 16#020#, wv(16#020#));
    chk_state(0, 16#020#, S);
    chk_state(1, 16#020#, S);

    scenario <= 5;
    report "5. write to a shared line invalidates the other copy";
    wr(0, 16#020#, x"BBBB0002");
    chk_state(0, 16#020#, M);
    chk_state(1, 16#020#, I);

    scenario <= 6;
    report "6. read of a line modified in the other cache";
    rd(1, 16#020#, x"BBBB0002");
    chk_state(0, 16#020#, S);
    chk_state(1, 16#020#, S);

    scenario <= 7;
    report "7. simultaneous writes to the same shared line";
    rd(0, 16#030#, wv(16#030#));
    rd(1, 16#030#, wv(16#030#));
    wr_both(16#030#, x"C0C0C0C0", 16#034#, x"C1C1C1C1");
    rd(0, 16#030#, x"C0C0C0C0");
    rd(0, 16#034#, x"C1C1C1C1");
    rd(1, 16#030#, x"C0C0C0C0");
    rd(1, 16#034#, x"C1C1C1C1");
    chk_state(0, 16#030#, S);
    chk_state(1, 16#030#, S);

    if errors = 0 then
      report "ALL TESTS PASSED";
    else
      report integer'image(errors) & " TEST(S) FAILED" severity error;
    end if;

    err_count <= errors;
    finished  <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    running <= false;
    wait;

  end process;

end architecture;
