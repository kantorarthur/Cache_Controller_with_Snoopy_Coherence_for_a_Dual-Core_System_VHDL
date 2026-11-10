library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cache_pkg.all;

entity hw_tester is
  generic (
    POLICY : repl_policy_t := LRU
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    step_mode    : in  std_logic;
    step_pulse   : in  std_logic;
    cpu0_req     : out std_logic;
    cpu0_we      : out std_logic;
    cpu0_addr    : out addr_t;
    cpu0_wdata   : out word_t;
    cpu0_rdata   : in  word_t;
    cpu0_ready   : in  std_logic;
    cpu1_req     : out std_logic;
    cpu1_we      : out std_logic;
    cpu1_addr    : out addr_t;
    cpu1_wdata   : out word_t;
    cpu1_rdata   : in  word_t;
    cpu1_ready   : in  std_logic;
    dbg_hit      : in  std_logic_vector(1 downto 0);
    dbg_miss     : in  std_logic_vector(1 downto 0);
    probe_active : out std_logic;
    probe_addr   : out addr_t;
    probe0_state : in  msi_t;
    probe1_state : in  msi_t;
    scenario     : out unsigned(2 downto 0);
    step_index   : out unsigned(5 downto 0);
    last_rdata   : out word_t;
    last_hit     : out std_logic;
    last_miss    : out std_logic;
    errors       : out unsigned(7 downto 0);
    waiting      : out std_logic;
    done         : out std_logic
  );
end entity;

architecture rtl of hw_tester is

  type op_kind_t is (OP_READ, OP_WRITE, OP_WRITE_BOTH, OP_STATE, OP_END);

  type op_t is record
    kind   : op_kind_t;
    sc     : natural range 0 to 7;
    core   : natural range 0 to 1;
    addr   : natural range 0 to 4095;
    data   : word_t;
    addr1  : natural range 0 to 4095;
    data1  : word_t;
    state  : msi_t;
  end record;

  constant PROGRAM_LEN : positive := 40;
  type program_t is array (0 to PROGRAM_LEN-1) of op_t;

  constant ZERO : word_t := (others => '0');

  function w(v : natural) return word_t is
  begin
    return std_logic_vector(to_unsigned(v, WORD_W));
  end function;

  function rd(sc : natural; core : natural; a : natural; expected : word_t) return op_t is
  begin
    return (OP_READ, sc, core, a, expected, 0, ZERO, I);
  end function;

  function wr(sc : natural; core : natural; a : natural; value : word_t) return op_t is
  begin
    return (OP_WRITE, sc, core, a, value, 0, ZERO, I);
  end function;

  function wr_both(sc : natural; a0 : natural; v0 : word_t; a1 : natural; v1 : word_t) return op_t is
  begin
    return (OP_WRITE_BOTH, sc, 0, a0, v0, a1, v1, I);
  end function;

  function st(sc : natural; core : natural; a : natural; expected : msi_t) return op_t is
  begin
    return (OP_STATE, sc, core, a, ZERO, 0, ZERO, expected);
  end function;

  function build_program return program_t is
    variable p : program_t := (others => (OP_END, 0, 0, 0, ZERO, 0, ZERO, I));
    variable n : natural := 0;
    procedure add(o : op_t) is
    begin
      p(n) := o;
      n := n + 1;
    end procedure;
  begin
    add(rd(1, 0, 16#000#, w(16#000#)));
    add(rd(1, 0, 16#004#, w(16#004#)));

    add(rd(2, 0, 16#040#, w(16#040#)));
    add(rd(2, 0, 16#000#, w(16#000#)));
    add(rd(2, 0, 16#080#, w(16#080#)));
    if POLICY = LRU then
      add(st(2, 0, 16#000#, S));
      add(st(2, 0, 16#040#, I));
    else
      add(st(2, 0, 16#000#, I));
      add(st(2, 0, 16#040#, S));
    end if;
    add(st(2, 0, 16#080#, S));

    add(wr(3, 0, 16#010#, x"AAAA0001"));
    add(st(3, 0, 16#010#, M));
    add(rd(3, 0, 16#050#, w(16#050#)));
    add(rd(3, 0, 16#090#, w(16#090#)));
    add(st(3, 0, 16#010#, I));
    add(rd(3, 1, 16#010#, x"AAAA0001"));

    add(rd(4, 0, 16#020#, w(16#020#)));
    add(rd(4, 1, 16#020#, w(16#020#)));
    add(st(4, 0, 16#020#, S));
    add(st(4, 1, 16#020#, S));

    add(wr(5, 0, 16#020#, x"BBBB0002"));
    add(st(5, 0, 16#020#, M));
    add(st(5, 1, 16#020#, I));

    add(rd(6, 1, 16#020#, x"BBBB0002"));
    add(st(6, 0, 16#020#, S));
    add(st(6, 1, 16#020#, S));

    add(rd(7, 0, 16#030#, w(16#030#)));
    add(rd(7, 1, 16#030#, w(16#030#)));
    add(wr_both(7, 16#030#, x"C0C0C0C0", 16#034#, x"C1C1C1C1"));
    add(rd(7, 0, 16#030#, x"C0C0C0C0"));
    add(rd(7, 0, 16#034#, x"C1C1C1C1"));
    add(rd(7, 1, 16#030#, x"C0C0C0C0"));
    add(rd(7, 1, 16#034#, x"C1C1C1C1"));
    add(st(7, 0, 16#030#, S));
    add(st(7, 1, 16#030#, S));

    return p;
  end function;

  constant PROGRAM : program_t := build_program;

  type tstate_t is (T_FETCH, T_ISSUE, T_WAIT, T_PROBE, T_COMPARE, T_NEXT, T_PAUSE, T_DONE);

  signal tst      : tstate_t := T_FETCH;
  signal pc       : natural range 0 to PROGRAM_LEN-1 := 0;
  signal op       : op_t := (OP_END, 0, 0, 0, ZERO, 0, ZERO, I);
  signal fin0     : std_logic := '0';
  signal fin1     : std_logic := '0';
  signal saw_miss : std_logic := '0';
  signal err_cnt  : unsigned(7 downto 0) := (others => '0');

  signal req0_r, we0_r, req1_r, we1_r : std_logic := '0';
  signal addr0_r, addr1_r             : addr_t := (others => '0');
  signal wdata0_r, wdata1_r           : word_t := (others => '0');
  signal probe_r                      : addr_t := (others => '0');
  signal probing                      : std_logic := '0';
  signal rdata_r                      : word_t := (others => '0');
  signal hit_r, miss_r                : std_logic := '0';

  function to_addr(a : natural) return addr_t is
  begin
    return std_logic_vector(to_unsigned(a, ADDR_W));
  end function;

begin

  process(clk)
    variable state : msi_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        tst      <= T_FETCH;
        pc       <= 0;
        req0_r   <= '0';
        req1_r   <= '0';
        probing  <= '0';
        err_cnt  <= (others => '0');
        rdata_r  <= (others => '0');
        hit_r    <= '0';
        miss_r   <= '0';
      else
        case tst is

          when T_FETCH =>
            op <= PROGRAM(pc);
            if PROGRAM(pc).kind = OP_END then
              tst <= T_DONE;
            elsif PROGRAM(pc).kind = OP_STATE then
              tst <= T_PROBE;
            else
              tst <= T_ISSUE;
            end if;

          when T_ISSUE =>
            fin0     <= '1';
            fin1     <= '1';
            saw_miss <= '0';
            if op.kind = OP_WRITE_BOTH then
              req0_r <= '1'; we0_r <= '1'; addr0_r <= to_addr(op.addr);  wdata0_r <= op.data;
              req1_r <= '1'; we1_r <= '1'; addr1_r <= to_addr(op.addr1); wdata1_r <= op.data1;
              fin0   <= '0';
              fin1   <= '0';
            elsif op.core = 0 then
              req0_r <= '1'; addr0_r <= to_addr(op.addr); wdata0_r <= op.data;
              if op.kind = OP_WRITE then
                we0_r <= '1';
              else
                we0_r <= '0';
              end if;
              fin0 <= '0';
            else
              req1_r <= '1'; addr1_r <= to_addr(op.addr); wdata1_r <= op.data;
              if op.kind = OP_WRITE then
                we1_r <= '1';
              else
                we1_r <= '0';
              end if;
              fin1 <= '0';
            end if;
            tst <= T_WAIT;

          when T_WAIT =>
            if (dbg_miss(0) = '1' and req0_r = '1') or (dbg_miss(1) = '1' and req1_r = '1') then
              saw_miss <= '1';
            end if;
            if cpu0_ready = '1' and req0_r = '1' then
              req0_r <= '0';
              fin0   <= '1';
              if op.core = 0 then
                rdata_r <= cpu0_rdata;
              end if;
            end if;
            if cpu1_ready = '1' and req1_r = '1' then
              req1_r <= '0';
              fin1   <= '1';
              if op.core = 1 and op.kind /= OP_WRITE_BOTH then
                rdata_r <= cpu1_rdata;
              end if;
            end if;
            if fin0 = '1' and fin1 = '1' then
              if op.kind = OP_READ and rdata_r /= op.data then
                err_cnt <= err_cnt + 1;
              end if;
              hit_r  <= not saw_miss;
              miss_r <= saw_miss;
              tst    <= T_NEXT;
            end if;

          when T_PROBE =>
            probe_r <= to_addr(op.addr);
            probing <= '1';
            tst     <= T_COMPARE;

          when T_COMPARE =>
            if op.core = 0 then
              state := probe0_state;
            else
              state := probe1_state;
            end if;
            if state /= op.state then
              err_cnt <= err_cnt + 1;
            end if;
            probing <= '0';
            tst     <= T_NEXT;

          when T_NEXT =>
            if step_mode = '1' then
              tst <= T_PAUSE;
            else
              pc  <= pc + 1;
              tst <= T_FETCH;
            end if;

          when T_PAUSE =>
            if step_pulse = '1' or step_mode = '0' then
              pc  <= pc + 1;
              tst <= T_FETCH;
            end if;

          when T_DONE =>
            null;

        end case;
      end if;
    end if;
  end process;

  cpu0_req     <= req0_r;
  cpu0_we      <= we0_r;
  cpu0_addr    <= addr0_r;
  cpu0_wdata   <= wdata0_r;
  cpu1_req     <= req1_r;
  cpu1_we      <= we1_r;
  cpu1_addr    <= addr1_r;
  cpu1_wdata   <= wdata1_r;
  probe_active <= probing;
  probe_addr   <= probe_r;
  scenario     <= to_unsigned(op.sc, 3);
  step_index   <= to_unsigned(pc, 6);
  last_rdata   <= rdata_r;
  last_hit     <= hit_r;
  last_miss    <= miss_r;
  errors       <= err_cnt;
  waiting      <= '1' when tst = T_PAUSE else '0';
  done         <= '1' when tst = T_DONE else '0';

end architecture;
