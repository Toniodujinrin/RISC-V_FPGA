# MARATHON — the full task list to the finished machine

Companion to [ROADMAP.md](ROADMAP.md). The roadmap is organised by *day*; this is organised by
*task*, flat and ranked, so you can pull the next item off the top without caring which day it was
supposed to happen on.

**The goal, stated once:**

> A 5-stage pipelined RV32I core with Zicsr, precise traps **and interrupts**, memory-mapped IO, an
> L1 cache in front of **external DRAM** on the Cyclone V, running GCC-compiled C — `fib_iter`,
> `fib_rec`, `factorial`, and everything the paper's final `RV32I46F_5SP` + SoC can do, up to and
> including Dhrystone.

**Deadline was Sunday 30 Aug 2026. Today is Mon 31 Aug.** The core deliverable (Tracks A+B+C) is
**green** — the pipeline executes GCC-compiled C programs self-checking against SIM_EXIT. What remains
is post-deadline stretch work: FPGA bring-up (Track F), CSRs/traps/interrupts (Track D), measurement
(Track G), and cache optimisation (Track E).

**What the two extra days bought: everything in Tracks A+B+C.** At the original ~16 h estimate,
A+B+C was the whole plan. With the deadline extended to Sunday and extra hours worked, all three
tracks are now complete:

- ✅ **Pipeline fully operational** — forwarding, hazard unit, LSU, branch predictor all wired and
  tested. Assembly regression suite green (9 programs). [Track A](#track-a--finish-the-pipeline-p0).
- ✅ **MMIO subsystem built** — APB bridge, SIM_EXIT, UART TX/RX, all behind the LSU's IO bypass.
  C programs reach the outside world. [Track B](#track-b--memory-plumbing-and-mmio-p0).
- ✅ **GCC-compiled C runs** — `crt0.s`, linker script, build flow all working. The C ladder has
  `fib_iter`, `sum`, `fact_rec` and `uart` (hello world) passing. [Track C](#track-c--run-c-p0).

**What is left is stretch work, not deadline work.** The core deliverable is done. Tracks D, E, F, G
are the path to the full paper parity and the board — each is independently valuable, and none is
required for the project to be called complete.

**Progress, 31 Aug.** The core deliverable is **complete**. All of Tracks A, B and C are green:

- ✅ **Tracks A+B+C all closed.** The pipeline executes GCC-compiled C, self-checking through
  SIM_EXIT. Assembly suite has 9 passing programs; C ladder has `fib_iter`, `sum`, `fact_rec`, and
  `uart` (hello world over real UART TX). See [ROADMAP § Running C](ROADMAP.md#running-c--what-it-actually-needs).
- ✅ **MMIO subsystem built** (30 Aug) — `rtl/io_apb_bridge.v`, `rtl/mmio.v`, `rtl/io/sim_exit.v`,
  `rtl/io/uart.v`. APB3 bridge with 4K-window decoder, SIM_EXIT at every offset in its window, real
  UART RTL with configurable frame format. The `io_*` bus no longer crosses the `data_path` boundary.
- ✅ **C build flow working** — `tb/cocotb/c_test/` has `crt0.s`, `link.ld`, `c_ctb.py`. Two-memory
  Harvard build: `objcopy --only-section=.text` for imem, `--only-section=.rodata/.data` for dmem.
  `crt0.s` sets `gp`/`sp`, clears `.bss`, calls `main`, stores result to SIM_EXIT.
- ✅ **Assembly suite expanded** — `hazards.s` added (distance-3 dependency, load/store width mix,
  branch/jump stress). 9 programs total: `r_type`, `b_type`, `loop`, `sl_type`, `sl_2_type`,
  `full_type`, `data_init`, `exit_check`, `hazards`.
- ✅ **Pipeline register forwarding capture** (29 Aug) — `ID_EX_reg` re-captures forwarded operands
  while stalled, fixing a distance-2 dependency across a memory stall that only `full_type.s` caught.

**What is left is post-deadline stretch work.** The remaining backlog:
- [Track D](#track-d--csrs-traps-interrupts-p1) — CSRs, traps, interrupts (~11 h)
- [Track F](#track-f--fpga-bring-up-on-the-cyclone-v-p1) — FPGA bring-up (~12 h)
- [Track E](#track-e--the-memory-system-caches-and-external-dram-p1) — external DRAM (~12 h)
- [Track G](#track-g--parity-and-measurement-p2) — measurement, Dhrystone (~7 h)

None of these are required for the project to be called complete. The core — a 5-stage pipelined
RV32I running GCC-compiled C — is finished.

**What this delivers strategically:** The pipeline is a finished, tested unit that executes real
compiled C. The golden ISA model in Python made testing cheap — adding a new `.s` test is
mechanical, and C programs self-check through SIM_EXIT without a golden model. The critical path
was: backing memory → IO slaves → `crt0.S` → C. All three are now done. The binding constraint
for the remaining stretch work is hours, not unknowns.

---

## Badges

Same convention as the roadmap, so the two documents read the same way.

| Difficulty | Meaning |
|---|---|
| `★☆☆` | Mechanical. Minutes to an hour. No design decision to make. |
| `★★☆` | Moderate. An hour or three. The shape is known; care required. |
| `★★★` | Hard. Half a day or more. This is where the schedule dies. |

| Importance | Meaning |
|---|---|
| `P0` | Blocks the goal. Without it there is no processor running C. |
| `P1` | Required for the stated goal (interrupts, DRAM, board bring-up). Cut only under fire. |
| `P2` | Parity/polish/measurement. First to go. |

- **⚠** — position forced by a dependency, not by difficulty. You cannot do it earlier even if it's easy.
- **🔥** — schedule risk. Any one of these can eat a full day if it goes wrong. There are six. Do them early, timebox them, and have the fallback ready.

---

## The ranking at a glance

**Core deliverable complete.** Everything below is post-deadline stretch, ranked by
independent value. Pull the next item off the top if you want to keep going.

| # | Task | | Est | Status |
|---|---|---|---|---|
| 1 | [Three scope decisions](#zero--decide-these-in-the-first-hour) | `★☆☆ P0` | 30 m | ✅ Decided — SDRAM, `.text` in M10K, timer+external interrupts |
| 2 | [Assembly regression suite green](#a5) | `★★☆ P0` | ~~2 h~~ | ✅ **9 programs green 31 Aug.** |
| 3 | [Backing memory](#b1) + [`SIM_EXIT`](#b2) + [IO slave](#b3) | `★★☆ P0` | ~~4 h~~ | ✅ **All done 30 Aug.** APB bridge, UART, sim_exit built. |
| 4 | [`crt0.S` + linker script](#c2) | `★★☆ P0` | ~~1.5 h~~ | ✅ **Done 30 Aug.** |
| 5 | [`fib_iter.c` → `factorial.c` → `fib_rec.c`](#c3) | `★★☆ P0` | ~~2 h~~ | ✅ **Done 30 Aug.** `fib_iter`, `sum`, `fact_rec`, `uart` pass. |
| 6 | [CSR file + Zicsr](#d1) | `★★☆ P1` | 2 h | Next — low risk, all simulation |
| 7 | [Trap controller (exceptions)](#d3) | `★★★ P1 🔥` | 3 h | After D1 |
| 8 | [Interrupts: CLINT + precise take point](#d5) | `★★★ P1 🔥` | 3 h | After D3 |
| 9 | [Board bring-up: pins, PLL, on-chip boot](#f2) | `★★☆ P1` | 3 h | Alternative to Track D |
| 10 | [UART TX + GPIO](#f5) | `★★☆ P1` | 2 h | After F2 |
| 11 | [Avalon adapter for the cache block port](#e4) | `★★★ P1 🔥` | 4 h | After board or CSRs |
| 12 | [Dhrystone](#g2) | `★★☆ P2` | 2 h | Needs D1 + E4 |

---

## Zero — decide these in the first hour

**✅ All three decided.** These were made at project start and are recorded here for reference:

- [x] ~~`★☆☆ P0` **D-A: which external memory.**~~ — **FPGA-side SDRAM.** The DE10-Standard
  carries both SDRAM (via Altera's SDRAM Controller IP) and HPS-side DDR3 (via FPGA-to-HPS bridge).
  SDRAM was chosen because it needs no software boot dependency — pure RTL, debuggable in simulation.
  DDR3 requires the HPS to boot first (preloader/u-boot to initialise the DDR PHY).

- [x] ~~`★☆☆ P0` **D-B: where `.text` lives.**~~ — **`.text` in on-chip M10K** (init'd from `.mif`),
  `.data`/`.bss`/stack in DRAM behind the D-cache. This gives a real external memory system on the
  data side while keeping one stall source in the pipeline instead of two. I-cache is [E6](#e6) as
  stretch.

- [x] ~~`★☆☆ P0` **D-C: interrupt sources.**~~ — **Timer + external.** A CLINT-style
  `mtime`/`mtimecmp` pair, and one level-sensitive external line ORed off the buttons. Software
  interrupts (`MSIP`) and a real PLIC are skipped — a single OR gate driving `MEIP` is enough.

---

## Fetching past the end of the program (28 Aug)

Worth writing down because the answer is a design principle, not a workaround, and because it decides
how the flashing story works later.

**Do not pad instruction memory with NOPs.** That was a testbench crutch, and it does not survive
contact with a compiler, real flash, or DDR. Three mechanisms replace it, in order of when they act:

1. **A correct program never runs off the end.** `crt0.S` ends in an infinite loop
   (`1: j 1b`, or `wfi`), so falling through is a fault path, not a state to design memory contents
   around. ARM's default `Reset_Handler` ends in `B .` for the same reason.
2. **The ISA reserves the escape hatch.** The RISC-V unprivileged spec defines the all-zero *and*
   all-ones instruction words as illegal **specifically to catch jumps into zeroed RAM or erased
   flash** — erased NOR flash reads `0xFFFF_FFFF`, zeroed RAM reads `0x0000_0000`. This core did not
   honour that: `control.v` cased on `op_code[6:2]` alone, so `32'd0` decoded as a LOAD. Fixed 28 Aug
   by requiring `op_code[1:0] == 2'b11`, which every 32-bit RISC-V instruction has.
3. **Then it becomes a trap.** [D3](#d3)'s `exception_detector` turns that same condition into an
   illegal-instruction exception with `mcause = 2` — the equivalent of a Cortex-M HardFault.

**The build flow is the standard one; do not write a custom assembler.** The tool that decides where
`.text`, `.data` and the stack live is the **linker script**, and it already exists:

```
gcc -march=rv32i -mabi=ilp32 -T link.ld -nostdlib crt0.S main.c -lgcc -o fw.elf
objcopy -O verilog fw.elf fw.mem     # $readmemh / simulation
objcopy -O ihex    fw.elf fw.hex     # or .mif for Quartus memory init
```

The `.mif`/`.hex` initialises block RAM at FPGA configuration time, which is the direct analogue of
programming STM32 flash: defined contents, no padding logic anywhere in the design.

### Where this is heading (the STM32-alike)

The end goal is a small MCU with a custom HAL, flasher and debugger. The pieces map onto standards
that already exist, which is the point — none of this needs inventing:

| STM32 | here |
|---|---|
| internal flash @ `0x0800_0000` | external SPI flash, or block RAM initialised from `.mif` |
| SRAM @ `0x2000_0000` | `data_mem` behind the L1 |
| peripherals @ `0x4000_0000` | the MMIO page at `0xF000_0000`, already cache-bypassed in `lsu.v` |
| vector table at flash base | RISC-V uses a reset vector plus `mtvec` for traps — simpler |
| SWD debug port | **RISC-V Debug Module over JTAG** (the official debug spec) |
| HAL | structs over the MMIO map |

Two things that make the debugger cheaper than it looks: the RISC-V Debug Specification's JTAG DTM is
what OpenOCD and GDB already speak, so the host side is off the shelf; and the FPGA already has a JTAG
port to reuse. [F7](#f7)'s clock-enable single-step is a stepping stone to the same place.

**None of this is deadline work** — items 1 and 3 are [C2](#c2) and [D3](#d3), the debugger is post-F.
Only the `control.v` guard was urgent, because it was a live hardware hang.

---

## Track A — finish the pipeline (P0)

**✅ Complete.** All pipeline stages, hazard unit, forwarding, LSU, and branch predictor are wired
and tested. 9 assembly programs pass against the golden ISA model. Nothing is left in this track.

<a name="a1"></a>
- [x] ~~`★★★ P0 🔥` **`rtl/hazard_detector.v` — the last blocker.**~~ — **done 25 Aug.** Module
  `hazard_unit`, pure combinational, elaborates and lints clean. Four jobs, all in:
  1. **Load-use stall** — `EX_mem_read && EX_rd != 0 && (EX_rd == ID_rs1 || EX_rd == ID_rs2)`.
     Stall IF/ID + PC, bubble ID/EX. The `EX_rd != 0` term also makes `rs1_used`/`rs2_used` decoder
     outputs unnecessary: `instruction_decoder.v:27-28` defaults `rs1`/`rs2` to 0 and only the arms
     that use them assign them, so `JAL`/`LUI`/`AUIPC` (and `rs2` on every I-type) can only match a
     producer whose `rd` is `x0` — which the term excludes. Non-local dependency, commented in both
     files.
  2. **Memory stall** — `req_stall` from the LSU ([A2](#a2)). Holds IF/ID, ID/EX **and** EX/MEM, and
     bubbles MEM/WB. Note the asymmetry with the load-use case: different registers freeze.
  3. **Flush on redirect** — `prediction_miss`, `EX_jump`, and later `trap`. Kill IF/ID and ID/EX.
  4. **Export `mem_advance`** — the MEM/WB clock enable, fed back into the LSU. This is what lets the
     LSU tell "a new access" from "the same access still parked in MEM". It must be
     `~mem_stall` where `mem_stall` means *specifically* what freezes EX/MEM: a load-use stall lets
     MEM drain and so must not appear in that term, and a MEM/WB flush counts as advancing.

  **Priority: `req_stall` outranks every redirect**, and getting this backwards is fatal — with the
  flush arms first, a mispredict during a memory stall emits flushes and *no* stalls, so EX/MEM
  advances and the in-flight load leaves MEM before its data returns. Letting the memory stall win is
  self-healing: it freezes ID/EX, so `prediction_miss`/`ex_jump` stay asserted off frozen contents
  until the stall lifts, and the pending redirect cannot be lost. Two bugs found and fixed on the way
  in: `mem_advance` assigned only under an `if` inferred a **latch** (it would have stuck high, and
  the LSU's `DONE` state would never engage), and `pc_flush` was declared but never assigned, sitting
  at X.

<a name="a2"></a>
- [x] ~~`★★★ P0 🔥` **A load/store unit to own the cache handshake.**~~ — **written 25 Aug,
  `rtl/lsu.v`.** Elaborates clean under `iverilog -g2001`. Solves the four defects it existed to
  solve, and the reasoning behind each is worth keeping:
  - **Issue-once.** `datapath.v:482` drove `cpu_data_in_valid` straight off `em_mem_read |
    em_mem_write`, re-issuing every stalled cycle — a duplicated store, which for `SB` into a
    cached block is silent corruption. The FSM now pulses the request once.
  - **Valid is held until accepted, not pulsed for one cycle.** The controller's real accept
    condition is `l1.v:166` — `cpu_data_in_valid & cpu_cache_ready` — and `cpu_cache_ready` is
    invisible from outside. After any miss the cache returns to IDLE with `ready` still low
    (`l1.v:705` re-raises it a cycle later, and the refill's write-enables hold it low longer),
    while the controller has already re-asserted `cpu_ready_out`. A one-cycle pulse into that
    window is silently dropped and the pipeline hangs forever. `cpu_ready_out` falling is used as
    the accept acknowledgement.
  - **`req_stall` is combinational**, `(em_mem_read | em_mem_write) && ~cpu_responded && ~DONE`.
    A registered stall can never be right: the flop reports the previous cycle, so the instruction
    it was protecting has already left MEM.
  - **A `DONE` state** covers a response arriving while something *else* is holding the MEM stage.
    Without it the access re-issues. Reached only when `mem_advance` is low on the response cycle.

  Still open on this module: the misalignment check ([A9](#a9)).

<a name="a3"></a>
- [x] ~~`★☆☆ P0` **⚠ Wire `forwarding_unit.v`'s `source_a`/`source_b` outputs, or delete them.**~~ —
  **dropped.** The module is `forward_a`/`forward_b` only and the datapath owns the mux, which is the
  right split. Two things about it worth knowing rather than rediscovering: the forward sources are
  `em_src` and `wb_src`, the *writeback-source muxes* rather than raw ALU results, so a load's data
  forwards through the ordinary EX/MEM path; and `EX_MEM_reg.r_data_2` is fed `rd_2_fwd`
  (`datapath.v:458`), so a `sw` of a just-computed value stores the new value. The `LW` → `SW` case
  needs no MEM→MEM forward — the load-use stall covers it, and a MEM→MEM path would only buy back the
  one bubble. That makes it a CPI optimisation, not a correctness fix.

<a name="a4"></a>
- [x] ~~`★☆☆ P0` **⚠ Drive `instruction_decoder.v`'s `r_imm`.**~~ — **done 25 Aug**, zero-extended
  immediate on every arm. One thing to settle before [D1](#d1) wires the CSR file to it: `r_imm` is
  **not** `zimm`. `zimm` is `instr[19:15]`, the rs1 field, and the datapath already sources it through
  `alu_src_1 = 2'b10` (`datapath.v:381`). What the SYSTEM arm carries is `instr[31:20]` — the **CSR
  address** — which is the field the CSR file actually needs. The `S`/`B`/`J`/`U` arms have no consumer
  at all (`wb_r_imm` is unused); either cut them and rename the port `csr_addr`, or record who reads
  them.

<a name="a8"></a>
- [x] ~~`★★☆ P0` **⚠ Wire `lsu.v` and `hazard_detector` into `datapath.v`.**~~ — **done 25 Aug.** `LSU`
  sits between EX/MEM and `D_CACHE` and feeds `BE_logic`; `HAZARD` drives all four register pairs'
  stall/flush plus the PC. Two things that changed shape while wiring: `control.v`'s `pc_stall` output
  is now `id_sys_busy` into the hazard unit rather than going to `pc_controller` directly, so there is
  one owner of the PC freeze; and the `io_*` bus is brought out to the `data_path`/`RV32I` boundary the
  same way instruction fetch is, since no slave exists yet. Both TODO stubs deleted.

<a name="a9"></a>
- [ ] `★☆☆ P1` **Misaligned load/store detection in the LSU.** `LW` off a non-multiple-of-4, `LH`/`SH`
  off an odd address. The check belongs in the `IDLE` issue path **ahead of the `is_io` split**, so a
  bad access traps instead of being routed anywhere — the cache would otherwise perform a wrong
  access silently. Cheap now, and it is the input `exception_detector.v` needs in [D3](#d3).

<a name="a5"></a>
- [x] ~~`★★☆ P0` **Get the assembly regression suite green, unpadded.~~ — **done 31 Aug.**
  `tb/cocotb/datapath` compares retired PC + all 32 registers against a golden ISA model per
  instruction. Adding a case is: write `asm/x.s`, add a `Settings(...)`, run.
  **End every program with `ebreak`** — that is what tells the golden to stop.

  **Nine programs green as of 31 Aug**, all self-checking against the golden model:

  - ✅ `r_type.s` — R and I arithmetic, back-to-back dependencies
  - ✅ `b_type.s` — every branch, taken and not, plus `jal`/`jalr` and two loops
  - ✅ `loop.s` — 100 iterations; also asserts the mispredict rate, see [A7](#a7)
  - ✅ `sl_type.s` / `sl_2_type.s` — every load/store width and offset, signed and unsigned
  - ✅ `full_type.s` — mixed, including `lui`/`auipc` and a distance-2 dependency across a cache stall
  - ✅ `data_init.s` — `.data`/`.rodata`/`.bss` init path end to end
  - ✅ `exit_check.s` — SIM_EXIT pass/fail mechanism
  - ✅ `hazards.s` — distance-3 dependency (write-first register file), load/store width mix, branch/jump stress

  **These found four real bugs the shorter tests could not**, all at the memory-stall boundary and none
  reachable before [B1](#b1) existed: stale load writeback, forwarding lost across a stall, the
  prediction skew, and a zeroed instruction word decoding as a load. Mutation-tested — `loop.s` and
  `full_type.s` are each the *only* program that catches their respective bug.

<a name="a6"></a>
- [x] ~~`★★☆ P1` **Static prediction first, dynamic second.**~~ — **moot 29 Aug.** The dynamic
  predictor works, so there is no reason to fall back to static. Note the advice was sound and the
  reason it was: the gshare path turned out to be a **correctness** bug, not a CPI one, and the
  pipeline was only provably correct while the predictor was (accidentally) inert.

<a name="a7"></a>
- [x] ~~`★★☆ P2` **Wire the BTB + gshare in and prove they work.**~~ — **done 29 Aug.** They were
  instantiated since 24 Aug but predicted taken *zero* times: the PHT read was registered while the BTB
  target was combinational, so `bp_taken` described the previous pc. `loop.s` now asserts the mispredict
  rate (**10/100**, was 100%). CPI on that loop ~1.10, was ~1.99.

  **"Not correctness — CPI only" was wrong**, and worth remembering: the skew redirected the pc for a
  non-branch, which reaches EX with `branch = 0`, so nothing flushed and there was no recovery. Both
  passing tests were blind to it. That is exactly the failure
  [B3](../ROADMAP.md#b3--branch_predictorv) predicted in the roadmap.

---

## Track B — memory plumbing and MMIO (P0)

**✅ Complete.** Both memories written and instantiated, APB bridge with UART and SIM_EXIT built.
The `io_*` bus no longer crosses the `data_path` boundary.

<a name="b1"></a>
- [x] ~~`★★☆ P0` **Fill `rtl/inst_mem.v` and `rtl/data_mem.v`.**~~ — **done 28 Aug**, and both are
  instantiated inside `data_path` rather than brought out to its boundary. Three things worth carrying
  forward:

  - **Fetch needed no stall and no second LSU.** A *fixed* latency is fixed by retiming: address the
    ROM with `if_pc_next` and its output register sits in parallel with the PC register instead of in
    series behind it. A stall is only required for *variable* latency, i.e. an I-cache ([E6](#e6),
    already `P2` and cut #3).
  - **`data_mem` is word-wide with a burst counter**, not block-wide and not byte-addressed. The
    counter *is* the parameterised latency this item asked for — realistic delay falls out of the
    structure instead of being injected — and it is the shape [E4](#e4)'s Avalon adapter needs.
  - **`mem_ready` is an accept signal, not a status flag.** `cache_controller` drops
    `mem_addr_in_valid` the cycle it sees it, so a burst driven off the input valids freezes on word
    two and hangs the core on the first miss. Caught by mutation testing, not by reading the code.

  Covered by `tb/tb_dmem.v`. **`data_mem` still has no `$readmemh`** — needed before [C3](#c3)'s
  `sum.c` rung, which is the first program with initialised globals.

<a name="b2"></a>
- [x] ~~`★☆☆ P0` **Build `SIM_EXIT` before anything else in this track.~~ — **done 30 Aug,
  `rtl/io/sim_exit.v`.** A store to `0xF000_00FC` makes the TB `$finish` with the value as exit code.
  `FINISH=0` for cocotb, which cannot survive an RTL `$finish`. Every C program is now a self-checking
  test.

<a name="b3"></a>
- [x] ~~`★★☆ P0` **MMIO decode in MEM, outside the cache.**~~ — **done 25 Aug in `rtl/lsu.v`.**
  `is_io = em_alu_result[31:28] == IO_PAGE` (parameterised, defaults `4'hF`), evaluated on the raw
  address in the issue cycle, so an IO access is never presented to the cache at all — the cache
  needed no changes and cannot cache what it never sees. IO shares the LSU's single wait state:
  `io_access_r` records which port the outstanding access used and the response side is a mux
  (`resp_valid`, `resp_data`), so IO gets the same issue-once, stall-until-response guarantee for
  free. `io_req` is a strict one-cycle pulse — that is what stops a UART write firing repeatedly
  while the pipeline is stalled. IO loads land in `be_cache_in` through the same path as cached
  loads, so `BE_logic` sign-extends a `char`-typed device register correctly.

- [x] ~~`★★☆ P0` **⚠ The IO slave block on the other end.~~ — **done 30 Aug.** `rtl/io_apb_bridge.v`
  (APB3 master, 4K-window decoder, `PSTRB` and lane alignment from `io_size`), `rtl/mmio.v` (bridge
  plus slaves, `N_C = 2`), `rtl/io/uart.v` (APB slave, full UART TX/RX with configurable frame).
  `io_slv_err` on decode error. No timeout in the bridge's ACCESS state — every populated window must
  drive `PREADY`.

<a name="b4"></a>
- [x] ~~`★☆☆ P0` **Sim UART: `$write("%c", data)` on a write to `UART_TX`.~~ — **done 30 Aug as
  real RTL, not a sim model.** `rtl/io/uart.v` is a full APB slave with TX/RX, configurable 5–8 data
  bits / 1–2 stop bits / odd-even parity, `RX_OVERRUN` gating. `putchar` enables the UART first
  (`UART_CONTROL = 0x0E`), then polls `TX_EMPTY` before every byte. `hello.c` prints "hello world"
  over the real UART.

<a name="b5"></a>
- [ ] `★★☆ P1` **⚠ Move the sub-word cache test into `tb/`.** The word/half/byte path was added to
  `l1.v` on 23 Aug and `tb/tb_ctrl.v` does **not** cover it — every store in that TB is at byte
  offset 0, where the old (wrong) and new (right) byte-lane expressions are identical. Word round
  trip, byte reads at all four offsets, half at both, and `SB`/`SH`/`SW` merges. `strlen.c` in the
  C ladder is otherwise the thing that discovers this, and by then you'll blame the compiler.

<a name="b6"></a>
- [ ] `★☆☆ P1` **Reconcile `BLOCK_BITS` through the hierarchy.** Today: `cache_controller` defaults
  to `32*8`, the inner `cache` to `64*8` with `WORD_OFF_BITS = 4`, `data_path` to `64*8`, and
  `RV32I.v` overrides the whole chain with `8*8 = 64` — while `WORD_OFF_BITS` stays at 3, implying
  256. Those cannot all be right. Pick one block size, derive every offset width from it, and note
  that this number becomes the DRAM burst length in [E4](#e4): a 512-bit block against a 16-bit
  SDRAM is a 32-beat burst per miss.

---

## Track C — run C (P0)

**✅ Complete.** The headline deliverable. GCC-compiled C programs run on the pipeline and
self-check through SIM_EXIT. The C ladder has `fib_iter`, `sum`, `fact_rec`, and `uart` passing.

<a name="c1"></a>
- [x] ~~`★★☆ P0 🔥` **RISC-V toolchain.**~~ — **done 27 Aug.** `binutils-riscv64-unknown-elf` +
  `gcc-riscv64-unknown-elf` at `/usr/bin/riscv64-unknown-elf-*`. `as` and `objcopy` are exercised on
  every datapath TB run, so the assembler half is proven rather than assumed. **The compiler half is
  not yet** — before [C2](#c2), verify with `-print-libgcc-file-name` that a **rv32i**
  libgcc multilib actually exists — with plain `-march=rv32i`, GCC emits calls to `__mulsi3`,
  `__divsi3`, `__udivsi3` and `__modsi3` for `*`, `/`, `%`, and a missing multilib is the classic
  first surprise here. Hardware M is an optimisation, not a requirement.

<a name="c2"></a>
- [x] ~~`★★☆ P0` **`crt0.S` + linker script + `hex` flow.~~ — **done 30 Aug.** `crt0.s` sets `sp`
  to `__stack_top`, sets `gp` to `__global_pointer$` (wrapped in `.option norelax`), zeroes `.bss`,
  calls `main`, stores return value to `SIM_EXIT`. Linker script has separate `MEMORY` regions for
  IMEM (32K) and RAM (4K), with `.text` at the reset vector and `.rodata`/`.data`/`.bss` in RAM.
  Build uses `gcc -nostdlib -nostartfiles -ffreestanding -O2 -lgcc` and `objcopy` twice (`.text`
  → imem image, `.rodata`+`.data` → dmem image).

<a name="c3"></a>
- [x] ~~`★★☆ P0` **The C ladder, in dependency order.~~ — **done 30 Aug.** Each rung adds exactly
  one requirement:

  | program | first needs | status |
  |---|---|---|
  | `fib_iter.c` — loop, no calls | registers + branches only | ✅ 30 Aug |
  | `sum.c` — sum a global array | `.data` init, `LW`, `gp` | ✅ 30 Aug |
  | `fact_rec.c` — recursive | stack, `sp`, `jal`/`jalr`, spill/reload | ✅ 30 Aug |
  | `uart.c` — hello world | MMIO UART + `putchar` | ✅ 30 Aug |

  Still on the ladder but not yet written: `strlen.c`/struct walk, `divmod.c`. The core is proven
  through `fact_rec` and the UART.

<a name="c4"></a>
- [ ] `★☆☆ P1` **⚠ Re-run the whole ladder at `-O2`.** `-O0` and `-O2` are near-different programs:
  `-O2` produces the tight register pressure, the deeper spills, and the branch patterns that find
  forwarding bugs `-O0` never touches. Cheap to run, and it's also what Dhrystone will use.

---

## Track D — CSRs, traps, interrupts (P1) — stretch, not started

This is where you go past the paper. The paper has exceptions; interrupts in a pipelined core are
strictly harder, because the trap arrives asynchronously and must still be *precise*. Low risk —
all simulation, golden model catches regressions.

<a name="d1"></a>
- [ ] `★★☆ P1` **`rtl/csr_file.v`.** Minimum: `mstatus`, `mtvec`, `mepc`, `mcause`, `mtval`, `mie`,
  `mip`, plus **`mcycle`/`minstret`** — you need those two for the DMIPS number in [G2](#g2), and
  they're free (two counters). Read-modify-write in one stage; a read returns the *old* value.

<a name="d2"></a>
- [ ] `★★☆ P1` **`CSRRW/S/C` + immediate forms**, decoded from the `I_TYPE_1` (`1110011`) arm in
  `control.v`, which has no SYSTEM arm at all yet. Needs [A4](#a4) for `zimm`. A CSR read in ID
  after a CSR write in EX is a hazard too — under this deadline the correct answer is **stall**, not
  a second forwarding network.

<a name="d3"></a>
- [ ] `★★★ P1 🔥` **`rtl/trap_controller.v` + `exception_detector.v`.** Detect illegal instruction,
  misaligned load/store, misaligned fetch, `ECALL`, `EBREAK`. On trap: `PC → mepc`, cause →
  `mcause`, jump to `mtvec`, flush; `MRET` restores. The hard part is not the CSR bookkeeping, it is
  that this is a **second control-flow override racing the branch flush** you built in Track A.
  Write the full priority order — trap > branch mispredict > jump > sequential — as a comment before
  writing the logic, and make `pc_controller.v`'s priority encoder the single place it's enforced.

<a name="d4"></a>
- [ ] `★★☆ P1` **`trap.S`** — `ECALL`, land at `mtvec`, `MRET` back, resume at `mepc+4`, registers
  intact. Then deliberately execute a garbage word and confirm illegal-instruction fires with the
  right `mcause`.

<a name="d5"></a>
- [ ] `★★★ P1 🔥` **Interrupts — the new thing.** Four parts, in this order:
  1. **CLINT-lite**: a 64-bit `mtime` counting core clocks and a `mtimecmp` compare register, both
     memory-mapped in the uncached `0xF` page. `mtime >= mtimecmp` → `MTIP`. Real CLINT uses
     `0x0200_xxxx`; putting it in your `0xF` page is a deviation worth one line in the README.
  2. **External line**: OR the button inputs into `MEIP`. Level-sensitive; the handler clears the
     source, not the pending bit.
  3. **The gate**: take an interrupt only when `mstatus.MIE && mie[x] && mip[x]`. On take, `MIE →
     MPIE`, `MIE = 0`, `MPP = 11`; `MRET` reverses it. `mcause` gets **bit 31 set** plus the cause
     code — that bit is what distinguishes 7 (timer) from 7 (store access fault).
  4. **The precise take point — this is the whole difficulty.** An interrupt is not tied to any
     instruction, so *you* choose where it lands. Pick one commit point (the MEM/WB boundary),
     take the interrupt only there, set `mepc` to the PC of the **oldest instruction not yet
     committed**, and flush everything younger. Two rules that will bite otherwise:
     **never take an interrupt mid-stall** (a load with a cache miss in flight must complete or be
     cleanly squashed — half a store is not precise), and **an exception from an older instruction
     outranks an interrupt** arriving the same cycle.

<a name="d6"></a>
- [ ] `★★☆ P1` **⚠ `irq.S` and then `irq.c`.** Assembly first: set `mtvec`, arm `mtimecmp`, enable
  `MIE`+`MTIE`, spin in a counting loop, confirm the handler fires N times and the loop's registers
  are untouched. Then C: the same test with the handler in C, `__attribute__((interrupt("machine")))`
  so GCC emits `MRET` and the full caller-saved prologue. **The C version is the real test** — it's
  the one that fails if your `mepc` is off by four, because a hand-written handler tends to be too
  short to notice.

<a name="d7"></a>
- [ ] `★☆☆ P2` **`FENCE`/`FENCE.I` as NOPs**, decoded and retired. That completes the paper's
  46-instruction set on paper; with a single hart and no store buffer past the WB FIFO, a NOP is
  a legitimate implementation. Say so in the README rather than leaving it looking like an oversight.

---

## Track E — the memory system: caches and external DRAM (P1) — stretch, not started

<a name="e1"></a>
- [ ] `★☆☆ P0` **⚠ `git tag` a known-good point before you touch memory.** The cache is a
  correctness-*neutral* optimisation: if any test result changes when it lands, the cache or the
  stall path is wrong, not the test. You need the before-picture to make that claim.

<a name="e2"></a>
- [ ] `★★☆ P1` **D-cache in sim first, against the latency-injecting model from [B1](#b1).** The
  4-way / 128-set / 64-byte `l1.v` is written and its controller TB passes. What is unproven is
  `l1.v` **behind a stalling pipeline**, which is a different thing entirely. Full regression suite
  must be bit-identical.

<a name="e3"></a>
- [ ] `★★☆ P1` **⚠ Exercise the write-back FIFO under pressure.** A miss moves a full block; the
  nastiest case is FIFO-full drain colliding with a new miss. `tb/tb_ctrl.v` covers that case and is
  worth trusting — but re-run it with the *core* as the requester, not a directed stimulus, because
  the access pattern from real compiled code is what fills a FIFO.

<a name="e4"></a>
- [ ] `★★★ P1 🔥` **Avalon-MM master adapter: cache block port → SDRAM controller.** The hardest new
  RTL in this document, and the gate on everything DRAM. It translates one block request
  (`mem_addr_in`/`mem_data_out`, `mem_ready`/`mem_data_in_valid`) into an Avalon burst of
  `BLOCK_BITS/32` beats, and reassembles a read burst back into one block. Watch for:
  **byte- vs word-addressing** (Avalon addresses are word-indexed by default and getting this wrong
  reads memory 4× off), **`waitrequest` can deassert mid-burst** so you must hold address and
  `burstcount` stable, and **`readdatavalid` is decoupled from the request** — count returned beats,
  never assume they arrive back-to-back. Write this against a *bus functional model* first; do not
  debug your first Avalon master on real silicon.

<a name="e5"></a>
- [ ] `★★☆ P1` **⚠ Bring the SDRAM controller up in Platform Designer.** Altera's SDRAM Controller
  IP, configured from the memory device's datasheet (row/col/bank widths, CAS latency, refresh
  interval). One PLL feeding two clocks: the controller/core clock, and the same clock
  **phase-shifted (~-3 ns)** to the SDRAM's `CLK` pin — that shift is a datasheet number, not a
  guess, and skipping it produces a memory that reads back plausible-looking garbage. Hold the core
  in reset until the controller's init sequence completes (~100 µs after power-up).

<a name="e6"></a>
- [ ] `★★★ P2` **I-cache — only after everything else is green.** Two independent stall sources into
  one pipeline is materially harder than one. Per [D-B](#zero--decide-these-in-the-first-hour),
  `.text` in on-chip M10K makes this optional right up until you want a program bigger than the
  block RAM.

<a name="e7"></a>
- [ ] `★★★ P2` **HPS-side DDR3 via the FPGA-to-HPS bridge.** The trophy version of "external DDR" —
  and a genuine day of work, most of it software (Platform Designer HPS instance, preloader to
  initialise the DDR PHY, `f2sdram` bridge, address-map translation) before one word moves. Only
  with the SDRAM path already working and committed.

---

## Track F — FPGA bring-up on the Cyclone V (P1) — stretch, not started

The `.qsf` currently has **no pin assignments at all** and the top level is a virtual-pin timing
probe with ~1130 ports. Getting from that to a real design on a board is its own track.

<a name="f1"></a>
- [ ] `★☆☆ P1` **⚠ A real SoC top level.** `RV32I.v` says it plainly in its own header comment: it
  exists to give the fitter a top whose ports can be `VIRTUAL_PIN`, and "when real memories land
  they get instantiated here and these ports go away". Do exactly that — instantiate the memories,
  the PLL, the UART and the GPIO, and let the port list collapse to a couple of dozen real signals.
  Then delete `syn/virtual_pins.tcl` from the flow so nobody accidentally fits the probe again.

<a name="f2"></a>
- [ ] `★★☆ P1` **Pin assignments + PLL + reset synchroniser.** Import the board's pin `.tcl` /
  `.qsf` from the vendor rather than typing 60 locations by hand — a single transposed SDRAM
  address pin costs you an afternoon of "the memory is haunted". Reset: async assert, **sync
  deassert**, off the PLL's `locked`.

<a name="f3"></a>
- [ ] `★★☆ P1` **Memory init the Quartus way.** `$readmemh` doesn't survive synthesis — convert the
  linked ELF to a `.mif`/`.hex` and attach it to the on-chip RAM IP or the inferred array's
  `ram_init_file` attribute. Then a **re-flash loop that is one command**: edit C → make → `.mif` →
  `quartus_cdb --update_mif` + `quartus_asm` → `quartus_pgm`. You will run this loop thirty times on
  Friday; every manual GUI step in it is thirty manual GUI steps.

<a name="f4"></a>
- [ ] `★★☆ P1` **Close timing, then read the fitter report properly.** You're at ~93 MHz against a
  100 MHz SDC; the SDRAM path may want a specific frequency anyway, so re-target the SDC to whatever
  the memory clock actually is rather than chasing a round number. Two things to check by eye rather
  than trust: whether `pht` (128×2 bits) landed in an M10K — spending a whole block on 256 bits of
  state is probably wrong versus MLAB — and whether the register file's **negedge write** inferred
  the way you expect. That half-cycle path is real and TimeQuest reports it; do not false-path it.

<a name="f5"></a>
- [ ] `★★☆ P1` **UART TX (then RX) + GPIO.** 115200-8-N-1, a divider off the system clock, a shift
  register, `tx_ready` in the status register — half a day if you write it from scratch, an hour if
  you drop in Altera's. GPIO is LEDs on `0xF000_0010` and buttons on `0xF000_0014`, and the buttons
  are also your external interrupt source from [D5](#d5). **Debounce them**, or every press fires
  the handler a dozen times and you'll suspect the interrupt logic.

<a name="f6"></a>
- [ ] `★☆☆ P1` **⚠ Run the C ladder on the board.** Same binaries, same expected results, output over
  the real UART instead of `$write`. A program that passes in sim and fails on the board is telling
  you about your memory init, your reset, or your timing closure — in that order of likelihood.

<a name="f7"></a>
- [ ] `★★☆ P2` **SignalTap on the retire signals** (PC, `rd`, write data at MEM/WB). When something
  fails only on hardware, this is what turns a week into an hour. Set it up *before* you need it —
  adding it later means another full compile at the exact moment you're out of time.

<a name="f8"></a>
- [ ] `★☆☆ P2` **The paper's clock-enable single-step debug feature.** Gate the core's clock enable
  from a button, so each press retires one instruction and the LEDs show state. Cheap, and it demos
  extremely well.

---

## Track G — parity and measurement (P2) — stretch, not started

<a name="g1"></a>
- [ ] `★☆☆ P2` **Count instructions and cycles for CPI.** `minstret`/`mcycle` are already in
  [D1](#d1); this is just reading them and dividing. Paper reference: 1.61 CPI.

<a name="g2"></a>
- [ ] `★★☆ P2` **Dhrystone 2.1.** Needs `-O2`, working `mcycle`/`minstret`, UART output, and enough
  RAM — which is exactly what Track E bought you. Paper's number: 646,640 instructions in 1,043,092
  cycles = **1.09 DMIPS/MHz**. Reproducing that is the cleanest one-line claim in the project.

<a name="g3"></a>
- [ ] `★★☆ P2` **Cache effectiveness numbers.** Hit rate and average memory access time on Dhrystone,
  with the cache and without (route around it). This is the part of the project the paper does not
  have at all, so it's the most publishable measurement available to you — and DRAM latency is what
  makes the number dramatic.

<a name="g4"></a>
- [ ] `★★☆ P2` **gshare vs. plain 2-bit.** Build the ~20-line `pht[pc[8:2]]` predictor as a drop-in
  and compare mispredicts and CPI on the same binaries. Quantifies what the BHR actually buys.

<a name="g5"></a>
- [ ] `★☆☆ P2` **`README.md` — the deviations.** Immediate generation (D1), gshare instead of the
  paper's 2-bit, the MMIO map, `FENCE`-as-NOP, the cache and DRAM that aren't in the paper at all,
  and the CLINT address choice. A project that documents where it departs from its source reads as
  deliberate; one that doesn't reads as incomplete.

---

## Definition of done

**Core deliverable (A+B+C) — ✅ complete 30 Aug:**

- [x] All test programs pass on the 5-stage core, unpadded
- [x] Pipelined core's retired state is checked instruction-by-instruction against a golden ISA model
- [x] Branch predictor demonstrably reduces mispredicts on a loop benchmark (10/100 vs 100/100)
- [x] `fib_iter.c`, `sum.c`, `fact_rec.c` — GCC-compiled at `-O2` — give correct results
- [x] UART prints "hello world" over MMIO; SIM_EXIT reports pass/fail to the TB

**Full project completion (stretch):**

- [ ] Every module lints clean under `verilator -Wall`
- [ ] Every rung of the C ladder passes, including `strlen.c`/`divmod.c`
- [ ] `ECALL` → handler → `MRET` round-trips; illegal instruction sets the right `mcause`
- [ ] A timer interrupt fires during a running C loop, the C handler returns, and the loop's state is intact
- [ ] MMIO verified uncached: a UART status poll terminates with the cache wired in
- [ ] Cache integration leaves every test result bit-identical
- [ ] A C program runs from the board with `.data` and stack in **external DRAM**
- [ ] `hello.c` prints over the real UART; LEDs and buttons work; a button raises an interrupt
- [ ] Timing closed at the chosen clock, with the fitter report read rather than assumed
- [ ] `README.md` documents every deviation from the paper
- [ ] Clean history, tagged at each milestone

---

## Triage — what to cut, and in what order

> **Updated 31 Aug.** The deadline has passed and the core deliverable is complete. The triage
> below is now **historical** — it describes the cuts that were made to reach Sunday's deadline.
> For post-deadline priorities, see [Time budget vs. reality](#time-budget-vs-reality).

**What was cut to reach the Sunday deadline:**

1. **HPS DDR3** ([E7](#e7)) → FPGA-side SDRAM. Was already the recommendation.
2. **All of Track G.** Measurement was the first thing to go — costs nothing but bragging rights.
3. **I-cache** ([E6](#e6)). `.text` in on-chip RAM is a legitimate design point.
4. **External DRAM entirely** ([E4](#e4)–[E5](#e5)) → cache backed by on-chip M10K.
5. **Interrupts** ([D5](#d5)–[D6](#d6)), keeping exceptions.
6. **Traps** ([D3](#d3)), keeping Zicsr.
7. **The dynamic predictor** ([A7](#a7)), keeping static predict-not-taken.
8. **The board** (Track F), keeping simulation.

**What was NOT cut:** Tracks A, B, and C. A pipelined core running compiled C was always the project.
Everything else is adjectives.

**What actually happened:** All of A, B, and C were delivered. The dynamic predictor (A7) was
**not** cut — it works and improves CPI from ~1.99 to ~1.10 on the loop benchmark. The board
(F) and CSRs/traps (D) remain as post-deadline stretch.

---

## Time budget vs. reality

**Updated 31 Aug — deadline passed, core deliverable complete.**

| Track | Est | Status |
|---|---|---|
| A — finish the pipeline | 7 h | ✅ **Done.** All pipeline stages, hazard unit, forwarding, LSU, predictor. |
| B — memory plumbing + MMIO | 4.5 h | ✅ **Done.** Both memories, APB bridge, UART, SIM_EXIT. |
| C — run C | 6 h | ✅ **Done.** Toolchain, crt0, linker script, C ladder through hello.c. |
| D — CSRs, traps, interrupts | 11 h | **Not started.** Stretch — paper parity for exceptions + interrupts. |
| E — cache + external DRAM | 12 h | **Not started.** Stretch — external DRAM behind the L1. |
| F — FPGA bring-up | 12 h | **Not started.** Stretch — the board. |
| G — measurement | 7 h | **Not started.** Stretch — Dhrystone, CPI, cache effectiveness. |

**What was delivered against the original plan:** Tracks A+B+C at ~17.5 h estimated, delivered in
~15 h of effective work (the golden ISA model removed the single-cycle-core oracle, saving ~3 h;
the toolchain install was faster than budgeted; the C ladder compiled cleanly on the first try).
The core deliverable — a 5-stage pipelined RV32I running GCC-compiled C — is finished.

**Remaining stretch work (post-deadline, ~42 h total):**

| Track | Est | What it buys |
|---|---|---|
| D — CSRs + traps + interrupts | 11 h | Paper parity (`RV32I46F_5SP`) + interrupts. Low variance, all sim. |
| F — FPGA bring-up | 12 h | The board. Higher variance, but the thing a person can watch. |
| E — external DRAM | 12 h | Real DRAM behind the L1. Needs F or can run standalone. |
| G — measurement | 7 h | Dhrystone, CPI, cache numbers. Needs D1 + E4. |

**Any one of D or F is a good next step.** D is lower risk (simulation only, golden model catches
regressions); F produces something visible. Neither is required for the project to be called
complete.
