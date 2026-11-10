library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cache_pkg.all;

entity basys3_top is
  generic (
    POLICY        : repl_policy_t := LRU;
    DEBOUNCE_TIME : positive := 1_000_000
  );
  port (
    clk  : in  std_logic;
    btnC : in  std_logic;
    btnR : in  std_logic;
    sw   : in  std_logic_vector(15 downto 0);
    led  : out std_logic_vector(15 downto 0);
    seg  : out std_logic_vector(6 downto 0);
    dp   : out std_logic;
    an   : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of basys3_top is

  signal por_count         : unsigned(3 downto 0) := (others => '0');
  signal rst_meta, rst_btn : std_logic := '1';
  signal rst               : std_logic := '1';
  signal step_mode_meta    : std_logic := '0';
  signal step_mode         : std_logic := '0';
  signal step_pulse        : std_logic;

  signal cpu0_req, cpu0_we, cpu0_ready : std_logic;
  signal cpu1_req, cpu1_we, cpu1_ready : std_logic;
  signal cpu0_addr, cpu1_addr          : addr_t;
  signal cpu0_wdata, cpu1_wdata        : word_t;
  signal cpu0_rdata, cpu1_rdata        : word_t;
  signal dbg_hit, dbg_miss             : std_logic_vector(1 downto 0);

  signal probe_active   : std_logic;
  signal tester_probe   : addr_t;
  signal probe_addr     : addr_t;
  signal probe0_state   : msi_t;
  signal probe1_state   : msi_t;

  signal scenario   : unsigned(2 downto 0);
  signal step_index : unsigned(5 downto 0);
  signal last_rdata : word_t;
  signal last_hit   : std_logic;
  signal last_miss  : std_logic;
  signal errors     : unsigned(7 downto 0);
  signal waiting    : std_logic;
  signal done       : std_logic;
  signal passed     : std_logic;
  signal failed     : std_logic;

  signal d3, d2, d1, d0 : std_logic_vector(6 downto 0);

  constant CH_BLANK : std_logic_vector(6 downto 0) := "0000000";
  constant CH_DASH  : std_logic_vector(6 downto 0) := "1000000";
  constant CH_P     : std_logic_vector(6 downto 0) := "1110011";
  constant CH_E     : std_logic_vector(6 downto 0) := "1111001";
  constant CH_M     : std_logic_vector(6 downto 0) := "0110111";
  constant CH_S     : std_logic_vector(6 downto 0) := "1101101";
  constant CH_I     : std_logic_vector(6 downto 0) := "0000110";

  function hex_char(v : std_logic_vector(3 downto 0)) return std_logic_vector is
  begin
    case v is
      when "0000" => return "0111111";
      when "0001" => return "0000110";
      when "0010" => return "1011011";
      when "0011" => return "1001111";
      when "0100" => return "1100110";
      when "0101" => return "1101101";
      when "0110" => return "1111101";
      when "0111" => return "0000111";
      when "1000" => return "1111111";
      when "1001" => return "1101111";
      when "1010" => return "1110111";
      when "1011" => return "1111100";
      when "1100" => return "0111001";
      when "1101" => return "1011110";
      when "1110" => return "1111001";
      when others => return "1110001";
    end case;
  end function;

  function msi_char(st : msi_t) return std_logic_vector is
  begin
    case st is
      when M => return CH_M;
      when S => return CH_S;
      when I => return CH_I;
    end case;
  end function;

begin

  process(clk)
  begin
    if rising_edge(clk) then
      rst_meta <= btnC;
      rst_btn  <= rst_meta;
      if por_count /= "1111" then
        por_count <= por_count + 1;
        rst       <= '1';
      else
        rst <= rst_btn;
      end if;
      step_mode_meta <= sw(15);
      step_mode      <= step_mode_meta;
    end if;
  end process;

  step_btn : entity work.debouncer
    generic map (
      STABLE_CYCLES => DEBOUNCE_TIME
    )
    port map (
      clk   => clk,
      btn   => btnR,
      pulse => step_pulse
    );

  system : entity work.dual_core_system
    generic map (
      POLICY            => POLICY,
      MEM_INIT_ON_RESET => true
    )
    port map (
      clk          => clk,
      rst          => rst,
      cpu0_req     => cpu0_req,
      cpu0_we      => cpu0_we,
      cpu0_addr    => cpu0_addr,
      cpu0_wdata   => cpu0_wdata,
      cpu0_rdata   => cpu0_rdata,
      cpu0_ready   => cpu0_ready,
      cpu1_req     => cpu1_req,
      cpu1_we      => cpu1_we,
      cpu1_addr    => cpu1_addr,
      cpu1_wdata   => cpu1_wdata,
      cpu1_rdata   => cpu1_rdata,
      cpu1_ready   => cpu1_ready,
      dbg_hit      => dbg_hit,
      dbg_miss     => dbg_miss,
      probe0_addr  => probe_addr,
      probe0_state => probe0_state,
      probe1_addr  => probe_addr,
      probe1_state => probe1_state,
      dbg_cache0   => open,
      dbg_cache1   => open,
      mon_cmd      => open,
      mon_addr     => open,
      mon_data     => open,
      mon_done     => open,
      mon_grant    => open,
      mon_flush    => open
    );

  tester : entity work.hw_tester
    generic map (
      POLICY => POLICY
    )
    port map (
      clk          => clk,
      rst          => rst,
      step_mode    => step_mode,
      step_pulse   => step_pulse,
      cpu0_req     => cpu0_req,
      cpu0_we      => cpu0_we,
      cpu0_addr    => cpu0_addr,
      cpu0_wdata   => cpu0_wdata,
      cpu0_rdata   => cpu0_rdata,
      cpu0_ready   => cpu0_ready,
      cpu1_req     => cpu1_req,
      cpu1_we      => cpu1_we,
      cpu1_addr    => cpu1_addr,
      cpu1_wdata   => cpu1_wdata,
      cpu1_rdata   => cpu1_rdata,
      cpu1_ready   => cpu1_ready,
      dbg_hit      => dbg_hit,
      dbg_miss     => dbg_miss,
      probe_active => probe_active,
      probe_addr   => tester_probe,
      probe0_state => probe0_state,
      probe1_state => probe1_state,
      scenario     => scenario,
      step_index   => step_index,
      last_rdata   => last_rdata,
      last_hit     => last_hit,
      last_miss    => last_miss,
      errors       => errors,
      waiting      => waiting,
      done         => done
    );

  probe_addr <= tester_probe when probe_active = '1' else
                x"00000" & sw(7 downto 0) & "0000";

  failed <= '1' when errors /= 0 else '0';
  passed <= done and not failed;

  led(2 downto 0)  <= std_logic_vector(scenario);
  led(3)           <= last_hit;
  led(4)           <= last_miss;
  led(10 downto 5) <= std_logic_vector(step_index);
  led(11)          <= '0';
  led(12)          <= waiting;
  led(13)          <= step_mode;
  led(14)          <= failed;
  led(15)          <= passed;

  process(sw, scenario, passed, failed, probe0_state, probe1_state, last_rdata)
  begin
    if sw(14) = '1' then
      if sw(13) = '1' then
        d3 <= hex_char(last_rdata(31 downto 28));
        d2 <= hex_char(last_rdata(27 downto 24));
        d1 <= hex_char(last_rdata(23 downto 20));
        d0 <= hex_char(last_rdata(19 downto 16));
      else
        d3 <= hex_char(last_rdata(15 downto 12));
        d2 <= hex_char(last_rdata(11 downto 8));
        d1 <= hex_char(last_rdata(7 downto 4));
        d0 <= hex_char(last_rdata(3 downto 0));
      end if;
    else
      d3 <= hex_char('0' & std_logic_vector(scenario));
      if failed = '1' then
        d2 <= CH_E;
      elsif passed = '1' then
        d2 <= CH_P;
      else
        d2 <= CH_DASH;
      end if;
      d1 <= msi_char(probe0_state);
      d0 <= msi_char(probe1_state);
    end if;
  end process;

  display : entity work.seg7_driver
    port map (
      clk    => clk,
      digit3 => d3,
      digit2 => d2,
      digit1 => d1,
      digit0 => d0,
      seg    => seg,
      an     => an
    );

  dp <= '1';

end architecture;
