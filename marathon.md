# MARATHON — the full task list to the finished machine

Companion to [ROADMAP.md](ROADMAP.md). The roadmap is organised by *day*; this is organised by
*task*, flat and ranked, so you can pull the next item off the top without caring which day it was
supposed to happen on.

**The goal, stated once:**

> A 5-stage pipelined RV32I core with Zicsr, precise traps **and interrupts**, memory-mapped IO, an
> L1 cache in front of **external DRAM** on the Cyclone V, running GCC-compiled C — `fib_iter`,
> `fib_rec`, `factorial`, and everything the paper's final `RV32I46F_5SP` + SoC can do, up to and
> including Dhrystone.

**Sprint 2 — Sat 5 Sep 2026, 20:00 → Mon 7 Sep evening.** Scope settled on a second pass:

- **SDRAM replaces `data_mem.v`** behind the existing `l1.v` D-cache. `SRAM_controller.v` was
  written against the ISSI `IS42S16320F` datasheet and its cpu port is already a drop-in for
  `data_mem`'s — seven of eight signals are a rename ([E12](#e12)).
- **A UART bootloader that splits its writes**: `.text` → on-chip M10K, `.data`/`.rodata` → SDRAM
  ([J6](#j6)). This is the mechanism `data_mem.v`'s own header comment says is missing.
- **CSRs, traps and interrupts** ([Track D](#track-d--csrs-traps-interrupts-p1)) — paper parity.
- **Harvard stays.** `inst_mem.v` is untouched, there is no I-cache and no arbiter;
  [Track H](#track-h--von-neumann-unified-memory-i-cache-arbiter-p2) is demoted to stretch.

**The honest arithmetic: ~22 h available against ~31.5 h.**

| Block | Est | |
|---|---|---|
| [E8](#e8)–[E12](#e12) SDRAM: finish, verify, swap in, board | 13 h | `WRITE_BURST` is empty and DQ has no output enable — the write path has never run. |
| [J1](#j1)–[J6](#j6) bootloader, both destinations | 5.5 h | Highest value per hour, but only on the board. |
| [D1](#d1)–[D4](#d4) CSRs + traps | 7 h | Low variance, all sim, plumbing already in the pipeline registers. |
| [D5](#d5)–[D6](#d6) interrupts | 6 h | `★★★ 🔥`. Cutting the I-cache means these no longer have to come first. |
| **Total asked** | **~31.5 h** | against ~22 h (3 h tonight, ~10 h Sun, ~10 h Mon) |

**Verdict: ~1.4× over — down from 1.8× before the restructure, still not a fit.** The memory work
plus the bootloader plus CSRs fits; traps and interrupts slip to mid-week. Full reasoning and the
hour-by-hour line in
[Sprint 2 cut line](#sprint-2-cut-line--what-actually-lands-by-monday).

---

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
**Re-ranked 5 Sep** for Sprint 2 — see [the cut line](#sprint-2-cut-line--what-actually-lands-by-monday).

| # | Task | | Est | Status |
|---|---|---|---|---|
| 1 | [Three scope decisions](#zero--decide-these-in-the-first-hour) | `★☆☆ P0` | 30 m | ✅ Decided — SDRAM, `.text` in M10K, timer+external interrupts |
| 2 | [Assembly regression suite green](#a5) | `★★☆ P0` | ~~2 h~~ | ✅ **9 programs green 31 Aug.** |
| 3 | [Backing memory](#b1) + [`SIM_EXIT`](#b2) + [IO slave](#b3) | `★★☆ P0` | ~~4 h~~ | ✅ **All done 30 Aug.** APB bridge, UART, sim_exit built. |
| 4 | [`crt0.S` + linker script](#c2) | `★★☆ P0` | ~~1.5 h~~ | ✅ **Done 30 Aug.** |
| 5 | [`fib_iter.c` → `factorial.c` → `fib_rec.c`](#c3) | `★★☆ P0` | ~~2 h~~ | ✅ **Done 30 Aug.** `fib_iter`, `sum`, `fact_rec`, `uart` pass. |
| 6 | [Finish the SDRAM controller](#e8) | `★★★ P1 🔥` | 6 h | **Do first.** `WRITE_BURST` empty, DQ has no output enable, 12 logic bugs |
| 7 | [Vendor SDRAM model](#e10) | `★★☆ P1` | 2 h | Read *and* write bursts. Not optional before the board |
| 8 | [Swap into `data_mem`'s socket](#e12) | `★★☆ P1` | 1 h | Near-pure rename; one missing `data_in_valid` |
| 9 | [Bootloader `.text` → M10K](#j1) | `★★☆ P1` | 3 h | No SDRAM dependency — can land standalone |
| 10 | [Bootloader `.data` → SDRAM](#j6) | `★★☆ P1` | 2.5 h | Needs E8. Port mux + init wait + 32 B padding |
| 11 | [SDRAM pins + PLL phase shift](#e11) | `★★☆ P1` | 4 h | Highest variance in the sprint |
| 12 | [CSR file + Zicsr](#d1) | `★★☆ P1` | 3 h | Plumbing already in EX_MEM/MEM_WB/control |
| 13 | [Trap controller (exceptions)](#d3) | `★★★ P1 🔥` | 4 h | Slips to Tuesday |
| 14 | [Interrupts: CLINT + precise take point](#d5) | `★★★ P1 🔥` | 6 h | Slips to Wednesday. No longer blocked by [H2](#h2) |
| 15 | [Von Neumann + I-cache + arbiter](#track-h--von-neumann-unified-memory-i-cache-arbiter-p2) | `★★★ P2` | 13 h | **Stretch.** Lifts the 32 KB `.text` ceiling |
| 16 | [Dhrystone](#g2) | `★★☆ P2` | 2 h | Needs D1 + real DRAM |
| 17 | [DOOM](#track-k--doom-p2--the-capstone-stretch) | `★★★ P2` | ~40 h | Needs E + H + J *finished*. [RV32M](#k1) is the gate |

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

## Track D — CSRs, traps, interrupts (P1)

*Not started. Sprint 2 target — see [the cut line](#sprint-2-cut-line--what-actually-lands-by-monday).*

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

## Track E — the memory system: caches and external DRAM (P1)

*Partly started 5 Sep: `rtl/SRAM_controller.v` written, 12 logic bugs open, `WRITE_BURST` empty. See [E8](#e8).*

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

<a name="e8"></a>
- [ ] `★★★ P1 🔥` **Finish `rtl/SRAM_controller.v` — hand-rolled, not the Altera IP.** Written 5 Sep
  against the ISSI `IS42S16320F` datasheet (`42-45R-S_86400F-16320F.pdf`): 8M × 16 × 4 banks, 13-bit
  row, 10-bit column, full-page burst terminated by BST, CL=2. Reviewed 5 Sep — it compiles clean
  under `iverilog` and the syntax is fixed, but **12 logic bugs are open** and three of them stop it
  dead. In severity order:
  1. **DQM tied high** — that is a mask, not an enable. Held high, DQ never leaves Hi-Z and every
     write is suppressed. Tie both low.
  2. **Read capture is two clocks early.** Registered command out + registered data in makes the
     round trip **CL + 2**, not CL. Wait `counter == tCAS` from a counter that is actually reset on
     entry to `READ_BURST` — it is not, today.
  3. **Refresh only runs after a CPU transaction.** `refresh_pending` is consumed in `PRECHARGE`
     only, so an idle core never refreshes and the array decays. `NORMAL_IDLE` has to service it.
  4. Column address truncated (`cpu_u_c_addr_reg` is `[4:0]` against a 6-bit source, so A9 is stuck
     at 0 and half of every row aliases), refresh interval drifts long, `REFRESH_PERIOD` should be
     390 not 391, `mem_ready` re-asserts mid-transaction in `ACTIVATE`, no `tRAS`, `tMRD` in the
     wrong units, burst-stop a cycle late.
  5. `WRITE_BURST` is empty. Note when writing it that **write data has zero latency** — the first
     word must be on DQ in the same cycle the WRITE command is latched — and that `tDPL` (10 ns)
     must clear before the precharge.

<a name="e9"></a>
- [ ] `★★☆ P1` **⚠ DQ is bidirectional; the module has two unidirectional ports and no output
  enable.** Either an `inout [15:0]` with the tri-state inside, or add a `mem_data_oe` and build
  `assign DQ = oe ? d : 16'bz` in `RV32I.v`. There is currently no way to release the bus, so the
  write path cannot work until this is decided. Decide it before writing `WRITE_BURST`, not after.

<a name="e10"></a>
- [ ] `★★☆ P1` **A vendor SDRAM model before the board.** Micron publishes a Verilog `mt48lc*` model
  that checks every timing arc and `$display`s the violation with the parameter name. Bring the
  controller up against that. Debugging a first SDRAM controller on real silicon, through a memory
  that answers with plausible-looking garbage when the clock phase is wrong, is the single most
  expensive way to find the DQM bug above.

<a name="e11"></a>
- [ ] `★★☆ P1` **SDRAM pins + the clock phase shift.** The `.qsf` has **5 pin assignments** — clk,
  reset_n, uart_rx, uart_tx, io_slv_err. SDRAM needs ~40 more. Import them from the DE10-Standard
  vendor `.qsf`; do not type them. One PLL, two outputs: the core/controller clock, and the same
  clock **phase-shifted ~-3 ns** to the memory's CLK pin. That shift is a datasheet number.


<a name="e12"></a>
- [ ] `★★☆ P1` **Swap `SRAM_controller.v` into `data_mem.v`'s socket in `datapath.v`.** Seven of the
  eight signals are a pure rename (table in [the cut line](#sprint-2-cut-line--what-actually-lands-by-monday)).
  Three things to get right:
  1. **The missing `data_in_valid`.** `data_mem.v` gates acceptance on
     `addr_in_valid && (!write_read || data_in_valid)`; `SRAM_controller` looks at `cpu_in_valid`
     alone. Today's master happens to raise both together — `l1.v`'s `M_PORT_FIFO_READ` sets
     `mem_addr_in_valid` and `mem_data_out_valid` on the same edge — so it works by luck. Add
     `cpu_data_in_valid` and replicate the `accept` term rather than relying on that.
  2. **`mem_ready` is low for the whole ~100 µs init**, where `data_mem`'s is high out of reset.
     This is a feature: the first load simply stalls until the SDRAM is ready, which gives you
     "hold the core until init completes" for free. Confirm the hazard unit is happy stalling that
     long rather than adding a separate gate.
  3. **`mem_ready` now deasserts spontaneously** during a periodic refresh, not only in response to
     a request. `l1.v` only ever reads it as `mem_addr_in_valid && mem_ready` at lines 313/323, so
     it degrades to a wait — no change needed, but do not "optimise" that check later.


---

## Track F — FPGA bring-up on the Cyclone V (P1)

*Partly done: [F1](#f1) and [F2](#f2) landed — `RV32I.v` is a real SoC top with a reset synchroniser, fitted 1 Sep at 56 % ALMs / ~93 MHz with 5 real pins.*

**Updated 5 Sep.** The virtual-pin probe is gone — `RV32I.v` is a real SoC top and the design fits
with clk, reset_n, uart_rx, uart_tx and io_slv_err as actual pins. What is left of this track is the
~40 SDRAM pins and the PLL ([E11](#e11)), GPIO, and the debug items below.

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

## Track G — parity and measurement (P2)

*Not started.*

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

## Track H — Von Neumann: unified memory, I-cache, arbiter (P2)

*New 5 Sep. **Demoted to stretch 5 Sep (second pass)** — `inst_mem.v` stays, no I-cache, no
arbiter this sprint. Kept in full because it is the track that lifts the 32 KB `.text` ceiling
([H2](#h2) is the gate) and because [Track K](#track-k--doom-p2--the-capstone-stretch) needs it.* The core is Harvard today: `inst_mem.v` is a synchronous ROM read one cycle ahead of the PC, and
`data_mem.v` sits behind `l1.v`. Unifying them is not a wiring change — it changes what the fetch
stage is allowed to assume.

<a name="h1"></a>
- [ ] `★★☆ P1` **One address map, one backing store.** Collapse `PROGRAM_FILE`/`DATA_FILE` into a
  single image and a single linker script output, `.text`/`.rodata`/`.data`/`.bss` in one contiguous
  region. `crt0.s` and `link.ld` change with it. Do this first and independently — the two-memory
  build is what every existing cocotb test loads, so the test harness moves in the same commit or
  nothing passes.

<a name="h2"></a>
- [ ] `★★★ P1 🔥` **Variable-latency instruction fetch.** This is the actual work in Track H, and it
  is worth budgeting more than it looks. Today `imem_out_valid` is true one cycle after the address,
  always, so IF never stalls on its own account — `datapath.v:102` even feeds it `if_pc_next`
  directly. Behind a cache, fetch can stall for tens of cycles, which means:
  - IF needs its own valid/ready handshake and a stall that is **independent** of `pc_stall`.
  - A **PC redirect while a fetch is in flight** must be handled — a mispredict resolves in EX and
    the fetch you launched two cycles ago is now garbage. Either tag fetches and discard the
    response, or hold the redirect until the fetch retires. Tagging is correct; holding is simpler
    and probably right for Monday.
  - The IF/ID register must distinguish "no instruction yet" (bubble, keep the PC) from "instruction
    is a NOP" (advance). `IF_ID_reg.v` already carries `instr_valid`; check it survives a multi-cycle
    stall rather than latching once.

<a name="h3"></a>
- [ ] `★★☆ P1` **`rtl/icache.v` — a read-only derivative of `l1.v`.** Strictly simpler than the
  D-cache: no dirty bits, no write-back FIFO, no sub-word access, no store path. Same block port
  (`mem_addr_in`, `mem_data_in`, `mem_ready`, `mem_data_in_valid`) so it drops onto the arbiter
  unchanged. Start direct-mapped, 64 sets × 32 B = 2 KB, and only go 2-way if the miss rate on the
  C ladder justifies it. **Needs an invalidate port** for [J4](#j4).

<a name="h4"></a>
- [ ] `★☆☆ P1` **`rtl/mem_arbiter.v` — fixed priority, D over I.** One block-granular request in
  flight at a time; no need for anything cleverer while the SDRAM controller can only service one
  burst anyway. **Fixed priority is the right call, and D-before-I is the right order**: a data miss
  is blocking an instruction that has already committed to executing, while an instruction miss is
  refilling a stream that a mispredict may be about to discard. Round-robin buys nothing here and
  costs you a starvation argument you'd have to make. Revisit only when the display DMA of
  [K4](#k4) becomes a third master — *that* one has a real-time deadline and outranks both.

<a name="h5"></a>
- [ ] `★★☆ P1` **⚠ Regression must be bit-identical.** Same rule as [E1](#e1): the I-cache is a
  correctness-neutral optimisation. `git tag` before H2 lands. All 9 assembly programs and the whole
  C ladder pass unchanged, or the stall path is wrong — not the tests.

<a name="h6"></a>
- [ ] `★★☆ P1` **⚠ Fit risk: you are at 56 % ALMs and 7 % block RAM.** The 1 Sep fit is 23,331 /
  41,910 ALMs with **40,553 registers** and only 405 K / 5.6 M block-memory bits used. That ratio
  says `l1.v`'s tag/valid/PLRU arrays inferred into flops rather than M10K. Bolting a second cache
  on top of that is how you fail the fitter rather than the simulator. Before H3 goes to hardware,
  read the map report for `l1.v` and push the arrays into block RAM — there are 481 unused M10Ks.

<a name="h7"></a>
- [ ] `★☆☆ P2` **Self-modifying code and `FENCE.I`.** Once fetch and data share a memory, a store
  can land in a line the I-cache holds. With no coherence, `FENCE.I` stops being a legal NOP
  ([D7](#d7)) and has to actually invalidate. The bootloader is the first real instance of this
  ([J4](#j4)) — note it in the README rather than discovering it as a hang.

---

## Track J — the UART hardware bootloader (P1)

*New 5 Sep.* **The highest value-per-hour item in this document.** Every program change currently costs a Quartus
recompile via the `.mif` loop in [F3](#f3). A bootloader replaces that with a serial write and a
button press. Build it against **on-chip M10K first** — that version has no dependency on Track E
and can be finished in an evening.

<a name="j1"></a>
- [ ] `★☆☆ P1` **Framing protocol.** Magic word, load address, byte count, payload, CRC or simple
  checksum, then a one-byte ack. Keep it dumb enough to drive from `python3 -m serial`. `uart.v`
  already has RX, so this is a state machine over a byte stream, not new IO.

<a name="j2"></a>
- [ ] `★★☆ P1` **`rtl/bootloader.v` + a write port on the memory.** An FSM that owns the memory
  while `core_reset` is held, streams bytes in, and releases. Targeting M10K this is a second write
  port on the inferred array (or an arbitrated single port — the core is in reset, so there is no
  contention). Targeting SDRAM it becomes a third master on [H4](#h4) and needs
  [E8](#e8)+[E9](#e9) finished first — which is exactly why the M10K version comes first.

<a name="j3"></a>
- [ ] `★☆☆ P1` **`tools/load.py`.** Reads the linked `.bin`, chunks it, waits for acks, prints a
  progress bar. Fifteen minutes of Python that you will use several hundred times.

<a name="j4"></a>
- [ ] `★★☆ P1` **⚠ Release sequence — the part that bites.** Reset the core *after* the last byte
  lands, and **invalidate the I-cache** ([H3](#h3)) as part of the release, or the first run after a
  load executes whatever the previous program left in the cache lines. If the D-cache is write-back
  and the bootloader wrote through the memory system rather than around it, the blocks must be
  flushed to the backing store before release too. Simplest correct answer for Monday: hold reset
  over the whole load and reset the caches with the core.

<a name="j5"></a>
- [ ] `★☆☆ P2` **Baud.** 115200 is fine for a 20 KB test program (~2 s). It is *not* fine for the
  4.2 MB WAD in [K8](#k8) — that is 6.1 minutes at 115200 and 46 s at 921600. Make the divisor a
  parameter now so raising it later is a re-fit and not a rewrite.

<a name="j6"></a>
- [ ] `★★☆ P1` **The `.data` → SDRAM path (revised scope, 5 Sep).** `.text` goes to M10K, everything
  else to SDRAM, so the loader needs a **destination field in the protocol, not just an address** —
  the two memories are separate address spaces in a Harvard machine and byte 0 is a legal address in
  both. Then:
  - **A 2:1 mux on `SRAM_controller`'s cpu port**, `l1.v` versus the bootloader, selected by
    `boot_active`. ~30 min. Switch it only while the controller is in `NORMAL_IDLE`; the core is in
    reset so there is no contention, but do not flip it mid-burst.
  - **Wait for `mem_ready` before the first `.data` byte.** The init sequence is ~5000 cycles and
    the controller ignores commands until it finishes. `reset_mem` — currently an unused port — is
    the natural place to hang this.
  - **Pad `.data` to a 32-byte boundary.** The controller only moves whole 256-bit blocks; a
    trailing partial block needs the linker script to pad or the loader to zero-fill.

---

## Track K — DOOM (P2) — the capstone stretch

*New 5 Sep.*

Not a joke target and not a small one: **~40 h on top of everything above**, and it needs Tracks
E, H and J *finished*, not merely started. It is listed here because it is a genuinely good forcing
function — it turns "the memory system works" into a claim with a frame rate attached.

**What DOOM actually demands.** It is fixed-point throughout, so no FPU and no RV32F — RV32I is
enough on paper. What it is not is *small*: `doom1.wad` (shareware) is 4.2 MB, and `doomgeneric`
wants roughly 8–16 MB of heap on top. That is comfortably inside the 64 MB on the board's SDRAM and
completely impossible in M10K, so **Track E is not optional for this** the way it is for everything
else in this document.

<a name="k1"></a>
- [ ] `★★★ P2` **RV32M — multiply and divide.** The single biggest performance item. `FixedMul` and
  `FixedDiv` are DOOM's inner loop; without the M extension GCC emits calls to libgcc's `__mulsi3` /
  `__divsi3`, which are tens of cycles each in software. You have **0 of 112 DSP blocks used** — a
  32×32 multiplier is nearly free, and a radix-2 restoring divider is ~32 cycles of trivial logic.
  Budget ~4 h, and expect it to matter more than any cache tuning. Est 4 h.

<a name="k2"></a>
- [ ] `★★★ P2` **SDRAM finished and fast.** All of [E8](#e8)–[E10](#e10), plus back-to-back bursts
  without a full precharge/activate cycle between them (row-hit detection — keep the row open and
  skip ACT when the next block is in the same row/bank). DOOM's working set thrashes; the difference
  between "correct" and "correct with an open-row policy" is roughly 2× on memory-bound code.
  Est 12 h.

<a name="k3"></a>
- [ ] `★★☆ P2` **VGA output.** The DE10-Standard has an ADV7123 triple 8-bit DAC on a 15-pin D-sub.
  640×480 @ 60 Hz off a 25.175 MHz pixel clock from the PLL; DOOM renders 320×200 at 8 bpp, so
  pixel-double to 640×400 and letterbox 40 lines. Palette is 256 × 24 bits — one M10K. Est 4 h.

<a name="k4"></a>
- [ ] `★★★ P2 🔥` **Display DMA and a real arbiter.** Scanout is a hard real-time master: 640×480×60
  = 18.4 M pixels/s, and at 8 bpp that is ~18 MB/s of continuous reads that **cannot** be late. This
  is the point where [H4](#h4)'s fixed priority is no longer adequate — the DMA needs a line FIFO,
  a high-water-mark request, and priority over both CPU ports, with the CPU getting whatever
  bandwidth is left in horizontal blanking. Get this wrong and the symptom is tearing or black
  scanlines, not a crash. Est 5 h.

<a name="k5"></a>
- [ ] `★★☆ P2` **Newlib + a heap.** `sbrk` against a real heap in SDRAM, `malloc`, `memset`/`memcpy`
  (the WAD loader leans on both), and enough `printf` to see the startup banner. `crt0.s` grows a
  proper `.bss` clear over a much larger region. Est 4 h.

<a name="k6"></a>
- [ ] `★★★ P2` **`doomgeneric` port.** Five functions: `DG_Init`, `DG_DrawFrame`, `DG_SleepMs`,
  `DG_GetTicksMs`, `DG_GetKey`. `DG_GetTicksMs` wants `mcycle` from [D1](#d1). The WAD is not on a
  filesystem, so stub `I_ReadFile`/`fopen` against a fixed SDRAM address where [J2](#j2) parked it —
  a read-only in-memory file shim is a couple of hundred lines and avoids ever writing an SD stack.
  Est 8 h.

<a name="k7"></a>
- [ ] `★★☆ P2` **Input.** Cheapest first light is the host terminal: map UART RX bytes to
  `DG_GetKey`, so WASD over the same serial link that loaded the program. Buttons and switches work
  for a demo; PS/2 is the "proper" answer and costs an extra evening. Est 2 h.

<a name="k8"></a>
- [ ] `★★☆ P2` **Getting 4.2 MB onto the board.** [J5](#j5) at 921600 baud is 46 s and needs no new
  hardware — do that first. SD over SPI is the better answer eventually and is its own afternoon.
  Est 3 h.

<a name="k9"></a>
- [ ] `★☆☆ P2` **⚠ Set the frame-rate expectation before you start, not after.** A 486DX2-66 ran
  DOOM at roughly 20–35 fps and is worth ~25 MIPS. This core at 50 MHz and CPI ~1.5 is ~33 MIPS
  *nominal*, but every SDRAM miss is 20+ cycles and the fitter currently reports Fmax ~93 MHz at
  56 % ALMs. Honest bracket: **low single-digit fps without [K1](#k1)**, and **~10–20 fps with**
  RV32M, a working I-cache and an open-row SDRAM policy. If the number matters more than the demo,
  K1 and K2 are where the hours go — not K3 or K6.

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

**Sprint 2 additions (5 Sep):**

- [ ] A program is loaded over UART and runs, with no Quartus recompile in the loop
- [ ] One memory: `.text` and `.data` in a single image, fetch and load/store through one arbiter
- [ ] The full regression suite is **bit-identical** with the I-cache in and out
- [ ] A timer interrupt is taken precisely while an I-cache miss is in flight
- [ ] `SRAM_controller.v` passes against a vendor SDRAM model with zero timing violations
- [ ] (K) DOOM boots to the title screen, with a measured frame rate written down

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

## Sprint 2 cut line — what actually lands by Monday

> **Revised 5 Sep, second pass.** The first version of this section recommended J → D → H
> (bootloader, then Track D, then start Von Neumann). **That recommendation is superseded.** The
> revised scope below — Von Neumann demoted to stretch, no I-cache, `inst_mem` stays, SDRAM dropped
> straight into `data_mem`'s socket, bootloader writing to *both* memories — is a better plan, and
> it changes which track should be the spine. Reasoning kept in full below.

**Revised scope, decided 5 Sep:**

- [Track H](#track-h--von-neumann-unified-memory-i-cache-arbiter-p2) → **stretch.** No Von Neumann
  unification, no I-cache, no arbiter this sprint. `inst_mem.v` stays as it is.
- **SDRAM replaces `data_mem.v` behind `l1.v`.** Same block port, same socket.
- **The bootloader splits its writes**: `.text` → on-chip M10K (`inst_mem`), `.data`/`.rodata` →
  SDRAM.
- Track D (CSRs, traps, interrupts) unchanged in content, moved behind the memory work.

**Why this is the right restructure.** Three things it gets right:

1. **It cuts the 13 h item with the worst variance and keeps the two with the best value.** Track H
   was ~40 % of the backlog and the only item that touches the fetch stage, which every test
   depends on.
2. **`SRAM_controller.v`'s cpu port is already a drop-in for `data_mem.v`.** This is not a
   coincidence and it is the part of an integration that normally costs a day:

   | `data_mem.v` | `SRAM_controller.v` | |
   |---|---|---|
   | `mem_ready` | `mem_ready` | ✓ |
   | `data_out_valid` | `data_out_valid` | ✓ |
   | `data_out` | `data_out` | ✓ |
   | `addr_in` | `cpu_addr_in` | ✓ rename |
   | `addr_in_valid` | `cpu_in_valid` | ✓ rename |
   | `data_in` | `cpu_data_in` | ✓ rename |
   | `write_read` | `cpu_write_read` | ✓ rename |
   | `data_in_valid` | — | **missing, see [E12](#e12)** |

   Both sides register `ready` and both use the same req/ready retire rule, so the handshake
   composes. Budget **1 h**, not a day.
3. **It solves the problem `data_mem.v`'s own header comment describes.** That comment says
   `.data`/`.rodata` "have to be loaded straight into this array" because the core has no data path
   to instruction memory. A bootloader that writes both memories over UART is exactly the missing
   mechanism — it replaces `$readmemb` on two files with a serial protocol, without needing von
   Neumann to do it.

**A consequence worth banking: cutting the I-cache un-blocks the Track D ordering.** The first
version of this section argued D5 had to come *before* H2, because variable-latency fetch adds a
second asynchronous stall source and interrupts must never be taken mid-stall. With H cut there is
no second stall source — fetch from `inst_mem` still never stalls — so **interrupts can safely land
after the memory work instead of before it.** That is what makes the reordering below legal.

The counter-risk: SDRAM behind `l1.v` stretches the single remaining stall from ~10 cycles
(`data_mem`'s 8-word burst) to **~35+** (ACT + CL + 16 beats + PRE, plus a possible refresh
collision). D5 does not get harder to write, but it gets much harder to be sloppy in — a
take-point bug that hid behind a 10-cycle stall will not hide behind a 35-cycle one.

**The arithmetic: ~31.5 h against ~22 h.** Better than the 42 h it replaces, still ~1.4× over.

| Item | Est |
|---|---|
| [E8](#e8) `WRITE_BURST` + [E9](#e9) DQ output-enable decision + the 3 blocking read bugs + 9 others | 6 h |
| [E10](#e10) vendor model, read *and* write bursts verified | 2 h |
| [E12](#e12) swap into `data_mem`'s socket | 1 h |
| [E11](#e11) SDRAM pins + PLL phase shift + fit + first light | 4 h |
| [J1](#j1)–[J3](#j3) `.text` → M10K write port, protocol, `load.py` | 3 h |
| [J6](#j6) `.data` → SDRAM: 2:1 port mux + wait-for-init | 2 h |
| [J4](#j4) release sequence | 0.5 h |
| [D1](#d1)+[D2](#d2) CSR file + Zicsr | 3 h |
| [D3](#d3)+[D4](#d4) trap controller + `trap.S` | 4 h |
| [D5](#d5)+[D6](#d6) CLINT + precise take point + `irq.c` | 6 h |
| **Total** | **31.5 h** |

**Recommended Monday line — memory work as the spine, Track D slips (~21.5 h):**

| | Block | Est | Running |
|---|---|---|---|
| Sat night | [E9](#e9) DQ decision, then [E8](#e8): `WRITE_BURST` + DQM + read capture + refresh-in-idle | 3 h | 3 h |
| Sun AM | [E8](#e8) remaining 9 bugs; [E10](#e10) vendor model green on read *and* write | 5 h | 8 h |
| Sun PM | [E12](#e12) swap for `data_mem`, full regression in sim; [J1](#j1)–[J3](#j3) `.text` bootloader | 4 h | 12 h |
| Sun eve | [J6](#j6) `.data` → SDRAM, port mux, init wait; [J4](#j4) release | 2.5 h | 14.5 h |
| Mon AM | [E11](#e11) pins + PLL phase shift + fit | 4 h | 18.5 h |
| Mon PM | **First light**: load a pattern into SDRAM over UART, read it back, then the C ladder | 2 h | 20.5 h |
| Mon eve | [D1](#d1)+[D2](#d2) CSR file + Zicsr | 3 h | 23.5 h |

**Monday evening deliverable: a board that takes programs over UART into both memories, running out
of real SDRAM.** Traps Tuesday, interrupts Wednesday. That is a demo; Track D is a claim. This
sprint buys the demo.

**If paper parity matters more than the board,** invert it: [E8](#e8)+[E10](#e10)+[E12](#e12)
(9 h, SDRAM verified in simulation only) + all of Track D (13 h) = 22 h, and defer [E11](#e11)
and the bootloader. The bootloader has near-zero value without the board, so these two orderings
are genuinely exclusive — pick one deliberately rather than starting both.

**"Almost done" is optimistic — read this before betting the sprint on it.** The *read* path is
close: the state machine, the init sequence, the mode-register word and the burst-stop logic are
all right in shape. The *write* path does not exist — `WRITE_BURST` is empty and there is no output
enable on DQ, so the controller cannot release the bus and has never moved a byte in either
direction. That matters more than it sounds, because writes are the **eviction path of a write-back
cache**: with SDRAM behind `l1.v`, the first dirty-line eviction exercises code that has never run.
Call it ~80 % of the read path and ~0 % of the write path, and budget [E8](#e8) at a full 6 h.

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

**Remaining stretch work — re-scoped 5 Sep (~105 h total, ~65 h excluding DOOM):**

| Track | Est | What it buys |
|---|---|---|
| J — UART bootloader | 5.5 h | Splits writes: `.text` → M10K, `.data` → SDRAM. Best value/hour, but only on the board. |
| D — CSRs + traps + interrupts | 12.5 h | Paper parity (`RV32I46F_5SP`) + interrupts. Low variance, all sim. |
| H — Von Neumann + I-cache + arbiter | 13 h | **Stretch as of 5 Sep.** Lifts the 32 KB `.text` ceiling; required by Track K. |
| E — SDRAM controller + board | 13 h | **Sprint 2 spine.** Drops into `data_mem`'s socket ([E12](#e12)). 12 bugs open, `WRITE_BURST` empty. |
| F — FPGA bring-up (remainder) | 6 h | Partly done — real SoC top and 5 pins fitted 1 Sep. GPIO, SignalTap, single-step left. |
| G — measurement | 7 h | Dhrystone, CPI, cache numbers. Needs D1 + real DRAM. |
| K — DOOM | ~40 h | The capstone. Needs E + H + J finished, and RV32M on top. |

**The two-day picture is in [Sprint 2 cut line](#sprint-2-cut-line--what-actually-lands-by-monday):
~23 h available, ~42 h asked. J and D fit with H started; SDRAM does not fit under any ordering.**

**Superseded 5 Sep (second pass).** The earlier argument here was that D must precede H, because
H adds a second asynchronous stall source that makes [D5](#d5)'s precise interrupt take point
materially harder. **H is now cut from the sprint entirely, which dissolves that constraint** —
fetch still never stalls, so interrupts can land after the memory work. E is the spine and D slips.
