<img width="1440" height="920" alt="Image" src="https://github.com/user-attachments/assets/f28b6691-a51d-4b34-b58c-90b4b171d469" />

# Cache Controller with Snoopy Coherence for a Dual-Core System

A VHDL model of two private caches kept coherent by the **MSI snoopy protocol** over a shared bus, verified by a self-checking testbench, plus a C++ desktop viewer that replays the simulation step by step.

Each core has its own N-way set-associative, write-back cache. When a core misses, upgrades a line, or evicts a modified line, its cache controller puts a transaction on the shared bus. The other controller snoops every transaction and reacts: it supplies a modified line, demotes it, or invalidates its own copy.

## Tech stack

| Part | Technology |
|---|---|
| Hardware description | **VHDL** (VHDL-93 compatible, also builds as VHDL-2008) |
| Simulation | **Xilinx Vivado** (XSim); also tested with **GHDL 4.1** |
| Simulation log | **JSON Lines**, written from VHDL with `std.textio` |
| Viewer language | **C++17** |
| GUI framework | **Dear ImGui 1.91.5** |
| Windowing / rendering | **GLFW 3.4** + **OpenGL 3** |
| JSON parsing | **nlohmann/json 3.11.3** |
| Build system | **CMake ≥ 3.20** (dependencies fetched with `FetchContent`) |


## Demo -- Running the predefined VHDL simulation and visualising it in the C++ GUI

https://github.com/user-attachments/assets/bffaf789-bc0e-498f-8fb3-650cb0ec1e53

## Context

**Cache line:** caches copy memory in fixed-size blocks called lines (16 bytes here). Each line in the cache stores its data, a *tag* (which memory line it is), and a coherence *state*.

**N-way set-associative cache:** the cache is split into *sets*; a memory line can be placed in any of the N *ways* of exactly one set. The address is split into three fields:

| Field | Bits (default config) | Role |
|---|---|---|
| Tag | 26 | identifies the line inside its set |
| Index | 2 | selects one of the 4 sets |
| Offset | 4 | selects the byte inside the 16-byte line |

**Write-back with write-allocate:** a write only updates the cache and marks the line as modified; memory is updated when the line is evicted. On a write miss, the line is first brought into the cache and then written.

**The coherence problem:** with two private write-back caches, both can hold a copy of the same line. If core 0 writes its copy, core 1 would keep reading the old value from its own cache. A coherence protocol prevents this.

**Snooping:** every cache controller watches (*snoops*) all transactions on the shared bus. When another cache asks for a line it holds, it reacts.

**MSI:** every cache line is in one of three states:

| State | Meaning |
|---|---|
| **M** (Modified) | the only valid copy, written locally; memory is stale |
| **S** (Shared) | clean, read-only copy; the other cache may also hold it |
| **I** (Invalid) | not present or invalidated |

## Motivation

This is my semester project for **Structure of Computer Systems** (Technical University of Cluj-Napoca, 2026–2027). The assignment asks for a cache controller for a dual-core system with private caches kept coherent by a snoopy protocol, designed and simulated in VHDL.

The VHDL simulation proves the design works through waveforms and assertions, but waveforms make it hard to *see* coherence happening. So the testbench also writes a log of every bus transaction and cache state change, and a small C++ viewer replays it: which core requested what, where the data came from, and how each line changed state.

## Architecture

<img width="1568" height="1056" alt="Image" src="https://github.com/user-attachments/assets/923c9616-29b1-4059-b760-712fff140dfc" />


| File | Entity | Role |
|---|---|---|
| `cache_pkg.vhd` | package | configuration constants, types (`msi_t`, `bus_cmd_t`, `cache_line_t`), address helpers |
| `main_memory.vhd` | `main_memory` | behavioral memory with a fixed latency; serves line fills and write-backs |
| `repl_unit.vhd` | `repl_unit` | LRU ages or FIFO pointers per set; outputs the victim way |
| `cache_controller.vhd` | `cache_controller` | cache storage + processor-side FSM + snoop FSM |
| `bus_arbiter.vhd` | `bus_arbiter` | grants the bus to one controller at a time, round-robin |
| `dual_core_system.vhd` | `dual_core_system` | top level: connects the controllers, arbiter and memory; multiplexes the bus |
| `tb_dual_core.vhd` | `tb_dual_core` | testbench: models both cores, runs the scenarios, writes the log |

## How it works

### 1. MSI transitions

<img width="1084" height="616" alt="Image" src="https://github.com/user-attachments/assets/6331f95e-1c16-4c3c-bfff-05e6902ccab3" />


| Bus transaction | Issued on | Reaction of the other cache |
|---|---|---|
| `BusRd` | read miss | line in M: supplies it and goes to S |
| `BusRdX` | write miss | line in M: supplies it and goes to I; line in S: goes to I |
| `BusUpgr` | write hit on a line in S | line in S: goes to I (no data transferred) |
| `Flush` | eviction of a line in M | ignored by the other cache; memory is updated |

### 2. Processor-side FSM (`proc_fsm`)

| State | What it does |
|---|---|
| `IDLE` | waits for a request from the core |
| `COMPARE` | splits the address, compares the N tags of the set. Read hit or write hit in M: done. Write hit in S: needs `BusUpgr`. Miss: picks a victim (an invalid way first, otherwise the replacement policy) |
| `WRITEBACK` | the victim is in M: writes it back with `Flush` before replacing it |
| `WAIT_GRANT` | requests the bus; if its S copy was invalidated while waiting, turns `BusUpgr` into `BusRdX` |
| `BUS_TRANS` | drives the command, stores the returned line, sets its state (S or M), then goes back to `COMPARE`, where the access now hits |

### 3. Snoop FSM (`snoop_fsm`)

| State | What it does |
|---|---|
| `SNOOP_IDLE` | watches the bus for a `BusRd`, `BusRdX` or `BusUpgr` issued by the other controller |
| `LOOKUP` | checks whether it holds that line and in which state |
| `FLUSH` | the line is in M: drives it on the bus, then goes to S (`BusRd`) or I (`BusRdX`) |
| `INVALIDATE` | the line is in S and the other cache wants to write it: goes to I |

Both FSMs live in one clocked process, because only one process may write the cache storage. When both need the storage in the same cycle, the snoop side has priority and the processor side waits one cycle.

### 4. Bus transaction

1. A controller asserts `bus_req`.
2. The arbiter grants the bus to one controller (round-robin when both request).
3. The granted controller drives the command and the line address (and the data for `Flush`).
4. The other controller snoops: if it holds the line in M, it asserts `snoop_flush` and drives the line on the bus.
5. After `MEM_LATENCY` cycles, memory asserts `bus_done`. With `snoop_flush`, memory stores the flushed line and the requester takes the same data from the bus (cache-to-cache transfer); otherwise memory supplies the line.

The bus is atomic: a transaction finishes before the next one is granted.

## Simulation scenarios

The testbench runs 7 scenarios and checks every read value and line state with assertions. Memory starts with each word at address `A` holding the value `A`, so a correct read is easy to recognize.

| # | Scenario | What is checked |
|---|---|---|
| 1 | **Hit and miss**: core 0 reads `0x000`, then `0x004` (same line) | 1 miss followed by 1 hit, correct data |
| 2 | **Replacement**: core 0 reads 3 lines that map to the same 2-way set | LRU evicts `0x040`; FIFO evicts `0x000` |
| 3 | **Write-back**: core 0 writes `0x010`, then forces it out of the cache | the modified line is flushed to memory; core 1 then reads the new value from memory |
| 4 | **Shared**: both cores read `0x020` | both copies in S |
| 5 | **Invalidation**: core 0 writes `0x020` | `BusUpgr`; core 0 in M, core 1 in I |
| 6 | **Cache-to-cache**: core 1 reads `0x020` | core 0 supplies the modified line; both copies in S |
| 7 | **Simultaneous writes**: both cores write the same shared line in the same cycle | one wins arbitration, the other is invalidated and retries with `BusRdX`; both writes survive |

Scenarios 4, 5 and 6 are the three coherence cases required by the assignment.

Expected end of the Tcl console:

```
Note: ALL TESTS PASSED
```

## Viewer

<!-- Add a screenshot: docs/viewer.png -->
<img width="1440" height="920" alt="Image" src="https://github.com/user-attachments/assets/f28b6691-a51d-4b34-b58c-90b4b171d469" />

The viewer reads `cache_log.jsonl` and shows, for every step:

- a diagram of the cores, caches, bus and memory, with the active data path highlighted;
- a sentence explaining the step, plus every line that changed state (for example `Cache 0, set 2, way 0: line 0x020 M -> S`);
- both caches as tables (set, way, state, line address, data), with M / S / I colored and changed rows highlighted;
- the memory lines written back so far;
- a list of scenarios and steps you can click to jump to.

| Key | Action |
|---|---|
| `→` / `←` | next / previous step |
| `Space` | play / pause |
| **Load** | reload the log after a new simulation |

## Requirements

**Simulation**
- Xilinx Vivado (any version with XSim), or GHDL

**Viewer**
- CMake 3.20 or later
- A C++17 compiler (GCC, Clang or MSVC)
- Git (CMake downloads Dear ImGui, GLFW and nlohmann/json at configure time)
- On Linux, the X11 and OpenGL development packages:

```bash
sudo apt install libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libgl1-mesa-dev
```

## Build and run

### 1. Clone the repository
```bash
git clone https://github.com/kantorarthur/Cache_Controller_with_Snoopy_Coherence_for_a_Dual-Core_System_VHDL.git
```
### 2. Run the simulation in Vivado

1. Open `Implementation_In_VHDL/Implementation_In_VHDL.xpr`.
2. Make sure `tb_dual_core` is the top of **Simulation Sources**.
3. Let the simulation run to the end. Vivado stops at 1000 ns by default, and the full run takes about 1.9 µs. Either press **Run All** after starting the simulation, or set it once in the Tcl console:

```tcl
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
```

4. Run **Simulation → Run Behavioral Simulation**.

The log is written to:

```
Implementation_In_VHDL/Implementation_In_VHDL.sim/sim_1/behav/xsim/cache_log.jsonl
```

### 3. Build the viewer

```bash
#Enter the viewer directory
cd Cache_Controller_with_Snoopy_Coherence_for_a_Dual-Core_System_VHDL/CPP_GUI

#Configure and compile
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

### 3. Run the viewer

```bash
./build/cache_viewer <path-to-cache_log.jsonl> [start-step]
```

From the `CPP_GUI` directory, after running the simulation:

```bash
./build/cache_viewer ../Implementation_In_VHDL/Implementation_In_VHDL.sim/sim_1/behav/xsim/cache_log.jsonl
```

On Windows (Visual Studio generator) the executable is in `build\Release\`:

```bat
build\Release\cache_viewer.exe ..\Implementation_In_VHDL\Implementation_In_VHDL.sim\sim_1\behav\xsim\cache_log.jsonl
```

## Configuration

All sizes are constants in `cache_pkg.vhd`, as powers of two:

| Constant | Default | Meaning |
|---|---|---|
| `OFFSET_W` | 4 | line size = 2^4 = 16 bytes |
| `INDEX_W` | 2 | number of sets = 2^2 = 4 |
| `WAY_W` | 1 | associativity = 2^1 = 2 ways |
| `MEM_LATENCY` | 4 | memory access time in clock cycles (minimum 4) |

The replacement policy is the `POLICY` generic (`LRU` or `FIFO`), set in `tb_dual_core.vhd`.

## Log format

Each line of `cache_log.jsonl` is one JSON event:

| `type` | Written when | Main fields |
|---|---|---|
| `config` | simulation start | `sets`, `ways`, `line_size`, `policy` |
| `scenario` | a scenario starts | `id`, `name` |
| `cpu` | a core's request completes | `core`, `op`, `addr`, `value`, `result` (hit / miss) |
| `bus_start` | a transaction appears on the bus | `core`, `cmd`, `addr` |
| `bus_end` | a transaction completes | `core`, `cmd`, `addr`, `source`, `mem_write`, `data` |
| `state` | any cache line changes | full contents of both caches |
| `end` | simulation end | `errors` |

## Design notes and limitations

- The design targets **simulation**. The memory is a behavioral model and the design has not been synthesized.
- The bus is **atomic** and each core has **one outstanding request** at a time.
- The protocol is plain **MSI**. Reading and then writing an unshared line costs two bus transactions (`BusRd`, then `BusUpgr`); MESI's Exclusive state would remove the second one.
- Cache-to-cache transfer also updates memory, so a line supplied by another cache always ends in S in both caches.
