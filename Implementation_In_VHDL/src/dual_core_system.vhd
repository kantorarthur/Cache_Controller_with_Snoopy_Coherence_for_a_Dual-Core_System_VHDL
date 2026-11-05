library ieee;
use ieee.std_logic_1164.all;
use work.cache_pkg.all;

entity dual_core_system is
  generic (
    POLICY : repl_policy_t := LRU
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    cpu0_req     : in  std_logic;
    cpu0_we      : in  std_logic;
    cpu0_addr    : in  addr_t;
    cpu0_wdata   : in  word_t;
    cpu0_rdata   : out word_t;
    cpu0_ready   : out std_logic;
    cpu1_req     : in  std_logic;
    cpu1_we      : in  std_logic;
    cpu1_addr    : in  addr_t;
    cpu1_wdata   : in  word_t;
    cpu1_rdata   : out word_t;
    cpu1_ready   : out std_logic;
    dbg_hit      : out std_logic_vector(1 downto 0);
    dbg_miss     : out std_logic_vector(1 downto 0);
    probe0_addr  : in  addr_t;
    probe0_state : out msi_t;
    probe1_addr  : in  addr_t;
    probe1_state : out msi_t;
    dbg_cache0   : out cache_array_t;
    dbg_cache1   : out cache_array_t;
    mon_cmd      : out bus_cmd_t;
    mon_addr     : out addr_t;
    mon_data     : out line_data_t;
    mon_done     : out std_logic;
    mon_grant    : out std_logic_vector(1 downto 0);
    mon_flush    : out std_logic_vector(1 downto 0)
  );
end entity;

architecture structural of dual_core_system is

  signal req, grant     : std_logic_vector(1 downto 0);
  signal cmd0, cmd1     : bus_cmd_t;
  signal addr0, addr1   : addr_t;
  signal data0, data1   : line_data_t;
  signal flush0, flush1 : std_logic;

  signal bus_cmd     : bus_cmd_t;
  signal bus_addr    : addr_t;
  signal bus_data    : line_data_t;
  signal bus_done    : std_logic;
  signal snoop_flush : std_logic;
  signal mem_rdata   : line_data_t;

begin

  cc0 : entity work.cache_controller
    generic map (
      POLICY => POLICY
    )
    port map (
      clk         => clk,
      rst         => rst,
      cpu_req     => cpu0_req,
      cpu_we      => cpu0_we,
      cpu_addr    => cpu0_addr,
      cpu_wdata   => cpu0_wdata,
      cpu_rdata   => cpu0_rdata,
      cpu_ready   => cpu0_ready,
      bus_req     => req(0),
      bus_grant   => grant(0),
      cmd_o       => cmd0,
      addr_o      => addr0,
      data_o      => data0,
      flush_o     => flush0,
      bus_cmd     => bus_cmd,
      bus_addr    => bus_addr,
      bus_data    => bus_data,
      bus_done    => bus_done,
      dbg_hit     => dbg_hit(0),
      dbg_miss    => dbg_miss(0),
      probe_addr  => probe0_addr,
      probe_state => probe0_state,
      dbg_cache   => dbg_cache0
    );

  cc1 : entity work.cache_controller
    generic map (
      POLICY => POLICY
    )
    port map (
      clk         => clk,
      rst         => rst,
      cpu_req     => cpu1_req,
      cpu_we      => cpu1_we,
      cpu_addr    => cpu1_addr,
      cpu_wdata   => cpu1_wdata,
      cpu_rdata   => cpu1_rdata,
      cpu_ready   => cpu1_ready,
      bus_req     => req(1),
      bus_grant   => grant(1),
      cmd_o       => cmd1,
      addr_o      => addr1,
      data_o      => data1,
      flush_o     => flush1,
      bus_cmd     => bus_cmd,
      bus_addr    => bus_addr,
      bus_data    => bus_data,
      bus_done    => bus_done,
      dbg_hit     => dbg_hit(1),
      dbg_miss    => dbg_miss(1),
      probe_addr  => probe1_addr,
      probe_state => probe1_state,
      dbg_cache   => dbg_cache1
    );

  arb : entity work.bus_arbiter
    port map (
      clk   => clk,
      rst   => rst,
      req   => req,
      done  => bus_done,
      grant => grant
    );

  mem : entity work.main_memory
    port map (
      clk         => clk,
      rst         => rst,
      bus_cmd     => bus_cmd,
      bus_addr    => bus_addr,
      bus_data    => bus_data,
      snoop_flush => snoop_flush,
      rdata       => mem_rdata,
      done        => bus_done
    );

  bus_cmd <= cmd0 when grant(0) = '1' else
             cmd1 when grant(1) = '1' else
             B_IDLE;

  bus_addr <= addr0 when grant(0) = '1' else
              addr1 when grant(1) = '1' else
              (others => '0');

  bus_data <= data0 when (grant(0) = '1' and cmd0 = B_FLUSH) or flush0 = '1' else
              data1 when (grant(1) = '1' and cmd1 = B_FLUSH) or flush1 = '1' else
              mem_rdata;

  snoop_flush <= flush0 or flush1;

  mon_cmd   <= bus_cmd;
  mon_addr  <= bus_addr;
  mon_data  <= bus_data;
  mon_done  <= bus_done;
  mon_grant <= grant;
  mon_flush <= flush1 & flush0;

end architecture;
