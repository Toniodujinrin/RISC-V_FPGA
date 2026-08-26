# MARATHON — the full task list to the finished machine

Companion to [ROADMAP.md](ROADMAP.md). The roadmap is organised by *day*; this is organised by
*task*, flat and ranked, so you can pull the next item off the top without caring which day it was
supposed to happen on.

**The goal, stated once:**

> A 5-stage pipelined RV32I core with Zicsr, precise traps **and interrupts**, memory-mapped IO, an
> L1 cache in front of **external DRAM** on the Cyclone V, running GCC-compiled C — `fib_iter`,
> `fib_rec`, `factorial`, and everything the paper's final `RV32I46F_5SP` + SoC can do, up to and
> including Dhrystone.

**Deadline: Friday 28 Aug 2026.** Today is Tue 25 Aug. That is **today's evening + Wed + Thu + Fri
≈ 32–36 working hours**, against a backlog below that totals ~70 h if you do all of it. So this
document is as much a *cut list* as a task list — see [Triage](#triage--what-to-cut-and-in-what-order)
and [Time budget](#time-budget-vs-reality) at the bottom. Read those two sections before you start,
not after.

**Progress, 25 Aug evening.** `rtl/lsu.v` and `rtl/hazard_detector.v` written and both now wired into
`datapath.v` — [A1](#a1), [A2](#a2), [A8](#a8) and [B3](#b3) closed, which were ranked 2, 3 and 5. The
whole core elaborates under `iverilog -g2012`. The critical path is now **IO slaves → backing memory →
regression suite**.

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

Strict do-order for the critical path. Everything in the tracks below hangs off this spine.

| # | Task | | Est | Why here |
|---|---|---|---|---|
| 1 | [Three scope decisions](#zero--decide-these-in-the-first-hour) | `★☆☆ P0` | 30 m | Every hour after this is spent on the wrong thing if you get the DRAM one wrong |
| 2 | [Assembly regression suite green](#a5) | `★★☆ P0` | 2 h | Your oracle. Debugging C on an unverified core is the classic way to lose a day |
| 3 | [Backing memory + `SIM_EXIT`](#b1) | `★★☆ P0` | 1.5 h | Turns every program into a self-checking test. Build before any C |
| 4 | [The IO slave block](#b3) | `★★☆ P0` | 1.5 h | The bypass is built; nothing answers on the other end of it yet |
| 5 | [Toolchain + `crt0.S` + linker script](#c1) | `★★☆ P0 🔥` | 2 h | Long pole with no RTL content — start it in the background early |
| 6 | [`fib_iter.c` → `factorial.c` → `fib_rec.c`](#c3) | `★★☆ P0` | 2 h | The headline deliverable. Everything below this line is *more*, not *instead* |
| 7 | [CSR file + Zicsr](#d1) | `★★☆ P1` | 2 h | Prerequisite for traps, interrupts, and the `mcycle` measurement |
| 8 | [Trap controller (exceptions)](#d3) | `★★★ P1 🔥` | 3 h | A second control-flow override racing the branch flush |
| 9 | [Interrupts: CLINT + precise take point](#d5) | `★★★ P1 🔥` | 3 h | The genuinely new thing vs. the paper. Hardest correctness problem in the doc |
| 10 | [Avalon adapter for the cache block port](#e4) | `★★★ P1 🔥` | 4 h | Hardest new RTL. Gates all of external DRAM |
| 11 | [Board bring-up: pins, PLL, on-chip boot](#f2) | `★★☆ P1` | 3 h | The QSF has **zero** pin assignments today |
| 12 | [UART TX + GPIO](#f5) | `★★☆ P1` | 2 h | Turns the board from "probably working" into "visibly working" |
| 13 | [Dhrystone](#g2) | `★★☆ P2` | 2 h | The paper's headline number. Pure bonus |

---

## Zero — decide these in the first hour

Three decisions, each of which changes what you build. Make them now, write the answer in
`README.md`, and don't revisit.

- [ ] `★☆☆ P0` **D-A: which external memory.** The device is `5CSXFC6D6F31C6` — a Cyclone V SX SoC
  part (DE10-Standard class). Such boards carry **two** external memories and they are not equally
  reachable from the FPGA fabric:

  | Path | What it costs you | Verdict |
  |---|---|---|
  | **FPGA-side SDRAM** (16-bit, via Altera's SDRAM Controller IP in Platform Designer) | One Avalon-MM master adapter, one PLL with a phase-shifted output clock. No software. | **Take this by Friday** |
  | **HPS-side DDR3** (32-bit, via the FPGA-to-HPS SDRAM bridge) | The HPS must be instantiated *and booted* — preloader/u-boot to bring up the DDR PHY — before the fabric can touch a single byte. Plus the bridge, plus the same adapter. | Stretch. It is a day of Linux-side work before one word transfers |

  Both are honestly describable as "external DRAM behind an L1 cache". The SDRAM path gets you
  there with RTL you can debug in simulation; the DDR3 path adds a software boot dependency to
  a hardware deadline. **Confirm which memories your specific board actually populates before
  committing** — check the board schematic, not this table.

- [ ] `★☆☆ P0` **D-B: where `.text` lives.** If instructions come from DRAM you *must* have an
  I-cache or fetch dies at ~20 cycles per instruction. **Recommendation: `.text` in on-chip M10K
  (init'd from a `.mif`), `.data`/`.bss`/stack in DRAM behind the D-cache.** That gives you a real
  external memory system on the data side — which is the interesting half — while keeping one
  stall source in the pipeline instead of two. I-cache moves to [E6](#e6) as stretch.

- [ ] `★☆☆ P0` **D-C: interrupt sources.** Minimum credible set is **timer + external**:
  a CLINT-style `mtime`/`mtimecmp` pair, and one level-sensitive external line ORed off the
  buttons. Skip software interrupts (`MSIP`) and skip a real PLIC — a single OR gate driving
  `MEIP` is enough to demonstrate the mechanism and costs 20 lines instead of 400.

---

## Track A — finish the pipeline (P0)

Nothing else in this document runs until this track is green. `rtl/datapath.v` wires all five stages
and executes real instructions; `rtl/lsu.v` now owns the memory handshake. What is left is the
hazard unit, and connecting the two.

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
- [ ] `★★☆ P0` **Get the assembly regression suite green, unpadded.** One command, run after every
  change. All seven Day-1 programs plus `hazard.S`: back-to-back dependent ALU ops, load-use,
  branch on a just-computed value, store of a just-loaded value, and a **distance-3 dependency**
  (that last one exercises the negedge write-first register file, which forwarding does not cover).
  This suite is your oracle for the rest of the week — every later failure gets bisected against it.

<a name="a6"></a>
- [ ] `★★☆ P1` **Static prediction first, dynamic second.** Tie `branch_prediction = 0`, resolve in
  EX, flush on miss. Get the pipeline *correct* before making it *fast*. The BTB and gshare
  predictor are both already written and lint-clean, so switching over later is a one-signal change.

<a name="a7"></a>
- [ ] `★★☆ P2` **Wire the BTB + gshare in and prove they work.** Not correctness — CPI only. Two
  assertions that matter: a 100-iteration loop mispredicts ~2 times not ~100 (it *predicts*), and a
  consistently-taken branch drives its counter to `2'b11` (it *trains*). A predictor that never
  learns still gives correct results, so only the second test can tell you it's alive.

---

## Track B — memory plumbing and MMIO (P0)

<a name="b1"></a>
- [ ] `★★☆ P0` **Fill `rtl/inst_mem.v` and `rtl/data_mem.v`.** Both are literally 0 bytes. They are
  the backing store behind the cache, not a thing the cache replaces: `l1.v`'s memory port is
  block-wide with a `mem_ready`/`mem_data_in_valid` handshake and something has to answer it.
  `tb/tb_ctrl.v` already has a model to borrow. Give the model a **parameterised latency** — hold
  `mem_ready` low for N cycles — so the stall path is exercised from the first bring-up rather than
  the first time it hits real DRAM.

<a name="b2"></a>
- [ ] `★☆☆ P0` **Build `SIM_EXIT` before anything else in this track.** A store to `0xF000_00FC`
  makes the TB `$finish` with the value as exit code. This is the single highest-leverage 20 lines
  in the document: it turns every C program from "stare at a waveform" into "pass or fail".

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

- [ ] `★★☆ P0` **⚠ The IO slave block on the other end.** Nothing answers `io_req` yet. Decode the
  register map ([Memory-mapped IO](ROADMAP.md#memory-mapped-io)) and implement `SIM_EXIT`, the sim
  UART, and GPIO behind it. **Slave contract:** sample `io_req` for one cycle, return `io_ack` with
  `io_data_out` valid alongside it — registering `io_req` into `io_ack` gives a 2-cycle stall, tying
  them combinationally gives 1. Tie `tx_ready` high in the sim model so polling loops fall straight
  through.

<a name="b4"></a>
- [ ] `★☆☆ P0` **Sim UART: `$write("%c", data)` on a write to `UART_TX`.** Two lines. `printf` works
  long before any UART RTL exists, and the real transmitter becomes an FPGA-only concern ([F5](#f5)).

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

The headline deliverable. Start [C1](#c1) early and in the background — it's a download, not a
thinking task, and it's the one item that can stall on something outside your control.

<a name="c1"></a>
- [ ] `★★☆ P0 🔥` **RISC-V toolchain.** `riscv64-unknown-elf-gcc` with `-march=rv32i -mabi=ilp32`,
  or your distro's `gcc-riscv64-unknown-elf`. Verify with `-print-libgcc-file-name` that a **rv32i**
  libgcc multilib actually exists — with plain `-march=rv32i`, GCC emits calls to `__mulsi3`,
  `__divsi3`, `__udivsi3` and `__modsi3` for `*`, `/`, `%`, and a missing multilib is the classic
  first surprise here. Hardware M is an optimisation, not a requirement.

<a name="c2"></a>
- [ ] `★★☆ P0` **`crt0.S` + linker script + `hex` flow.** `_start` sets `sp` to the top of RAM, sets
  `gp` to `__global_pointer$` (wrapped in `.option norelax`, or the relaxation eats it), zeroes
  `.bss`, `call main`, then stores the return value to `SIM_EXIT`. Linker script puts `.text` at the
  reset vector and `.data`/`.bss` in RAM. Then `objcopy -O verilog` (or a `.mif` for Quartus, see
  [F3](#f3)) into whatever `$readmemh` expects. Sanity-check the very first program by
  `objdump -d`-ing it and reading the first ten instructions by eye.

<a name="c3"></a>
- [ ] `★★☆ P0` **The C ladder, in dependency order.** Each rung adds exactly one requirement, which
  is the whole point — when rung 4 fails you know it's the byte path, not "C doesn't work":

  | program | first needs |
  |---|---|
  | `fib_iter.c` — loop, no calls | registers + branches only; runs before memory works at all |
  | `factorial.c` — iterative then recursive | same, then the stack |
  | `sum.c` — sum a global array | `.data` init, `LW`, `gp` |
  | `fib_rec.c` — recursive | stack, `sp`, `jal`/`jalr`, spill/reload |
  | `strlen.c` / struct walk | `LB`/`LBU`, `SB` — the [B5](#b5) path |
  | `divmod.c` | libgcc soft mul/div |
  | `hello.c` | MMIO UART + `putchar` |

  Check results by storing to a known address and asserting in the TB, exactly like the `.S` tests.
  Do not depend on `printf` before `hello.c` — a failing `printf` and a failing core look identical.

<a name="c4"></a>
- [ ] `★☆☆ P1` **⚠ Re-run the whole ladder at `-O2`.** `-O0` and `-O2` are near-different programs:
  `-O2` produces the tight register pressure, the deeper spills, and the branch patterns that find
  forwarding bugs `-O0` never touches. Cheap to run, and it's also what Dhrystone will use.

---

## Track D — CSRs, traps, interrupts (P1)

This is where you go past the paper. The paper has exceptions; interrupts in a pipelined core are
strictly harder, because the trap arrives asynchronously and must still be *precise*.

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

## Track F — FPGA bring-up on the Cyclone V (P1)

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

## Track G — parity and measurement (P2)

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

- [ ] Every module lints clean under `verilator -Wall`
- [ ] Full assembly suite passes on the 5-stage core, unpadded
- [ ] `fib_iter.c`, `factorial.c`, `fib_rec.c` — GCC-compiled at `-O0` **and** `-O2` — give correct results
- [ ] Every rung of the C ladder passes, `hello.c` included
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

Protect the working core above everything. Cut from the bottom:

1. **HPS DDR3** ([E7](#e7)) → FPGA-side SDRAM. Already the recommendation, not really a cut.
2. **All of Track G.** Measurement is the first thing to go and costs you nothing but bragging rights.
3. **I-cache** ([E6](#e6)). `.text` in on-chip RAM is a legitimate design point, not a compromise.
4. **External DRAM entirely** ([E4](#e4)–[E5](#e5)) → cache backed by on-chip M10K. You keep the
   whole cache hierarchy and the stall path; you lose only the word "external". This is the biggest
   single hour-saver in the document if Thursday goes badly.
5. **Interrupts** ([D5](#d5)–[D6](#d6)), keeping exceptions. `RV32I46F` is the paper's own endpoint.
6. **Traps** ([D3](#d3)), keeping Zicsr. `RV32I43F` is still a named milestone in the paper.
7. **The dynamic predictor** ([A7](#a7)), keeping static predict-not-taken. Costs CPI, never correctness.
8. **The board** (Track F), keeping simulation. A verified core in sim beats a half-fitted one.

Note what is *not* on this list: Tracks A, B and C. A pipelined core running compiled C is the
project. Everything else is adjectives.

---

## Time budget vs. reality

| Track | Est | Cumulative |
|---|---|---|
| A — finish the pipeline | 7 h | 7 h |
| B — memory plumbing + MMIO | 4.5 h | 11.5 h |
| C — run C | 6 h | 17.5 h |
| D — CSRs, traps, interrupts | 11 h | 28.5 h |
| E — cache + external DRAM | 12 h | 40.5 h |
| F — FPGA bring-up | 12 h | 52.5 h |
| G — measurement | 7 h | 59.5 h |

Against **~32–36 hours** available — the LSU banked about 3.5 h of that. So the honest read:
**A + B + C + D lands right at the limit**, and that is already a pipelined RV32I core with
interrupts, MMIO and compiled C — everything in the goal statement except the board and the DRAM.

Two ways to spend the remaining budget, and they are mutually exclusive by Friday:

- **The memory system** (E): cache in front of external DRAM, in simulation, with the numbers from
  [G3](#g3). Debuggable, low-variance, and it's the half that isn't in the paper.
- **The board** (F): the core on real silicon with a UART and blinking LEDs. Higher variance —
  pin assignments and timing closure are exactly the tasks that turn into a lost day — but it is
  the thing you can put in front of a person.

**Pick one on Wednesday night, when you know how Track A actually went.** Trying for both is how you
get a half-finished DRAM controller *and* a design that doesn't fit, on Friday afternoon, with
nothing to show. If Track A is green by Wednesday evening, take F — a working board demo is worth
more than a simulated cache. If Track A slipped, take E and keep everything in the simulator where
you can still debug it.
