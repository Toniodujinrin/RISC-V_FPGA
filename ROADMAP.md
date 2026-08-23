# BASIC_RV32s Implementation Roadmap

Reproducing **RV32I46F_5SP** from *BASIC_RV32s: An Open-Source Microarchitectural Roadmap for RISC-V RV32I* (Kang & Choi, ISOCC 2025) — `2510.15887v1.pdf`.

- **Start:** Sat 22 Aug 2026
- **Target:** Sun 23 Aug (core done) → **hard deadline Tue 25 Aug**
- **Toolchain present:** `iverilog`, `verilator`, `gtkwave`, `cocotb` (in `.venv`)
- **Toolchain missing:** RISC-V GCC, FPGA vendor tools — see [Day 0](#day-0--saturday-morning-unblock-3-h)

---

## Scope call (read this first)

The paper covers two halves: **(a)** an incrementally-built pipelined core, **(b)** an SoC with UART + GPIO + Dhrystone synthesised at 50 MHz on Artix-7. Half (a) is achievable by Tuesday. Half (b) — plus the L1 cache integration you want, which is **not in the paper at all** (the paper's memories are plain LUT-based distributed RAM) — is more than 4 days of work if you're also debugging a first-time pipeline.

So this plan commits to a **primary target** and treats the rest as sequenced stretch:

| | Deliverable | When |
|---|---|---|
| **P0** | RV32I 5-stage pipelined core, forwarding + hazard unit + 2-bit dynamic predictor, passing self-checking sim tests | **by Mon 24** |
| **P1** | Zicsr + trap/exception handling (`RV32I43F` → `RV32I46F`) | **Mon 24 – Tue 25** |
| **P2** | `rtl/l1.v` wired in as the core's memory, core stalls on miss | **Tue 25** |
| **S1** | FPGA synthesis + UART SoC on your board | after Tue |
| **S2** | Dhrystone 2.1 + DMIPS/MHz measurement | after Tue |

The one design decision that makes P2 cheap is in [Day 1](#the-memory-interface-decision-do-this-once-get-it-right): **give the core a `valid`/`ready` stalling memory interface from the very first single-cycle version.** Then on Tuesday the cache swaps in behind an interface the pipeline already respects, instead of being surgery on a finished design.

> **Target board: Intel Cyclone, Quartus toolchain.** The existing `(* ramstyle = ... *)` attributes are already correct Intel syntax and stay as-is. This differs from the paper's Xilinx Artix-7, so expect different resource numbers and a different UART primitive in S1. Everything before S1 is vendor-neutral.

---

## Where the code actually stands

Compile-checked with `iverilog -g2012` on 22 Aug:

| File | Lines | Compiles | Status |
|---|---|---|---|
| `rtl/riscv_defs.vh` | 48 | — | 16 ALU ops (4-bit field, **full**) + instruction classes. See [D5](#d5-shared-constants) |
| `rtl/alu.v` | 43 | ✅ | **Done 23 Aug** — `ADD_C` added, `` `PC `` retired, lints clean. See [B1](#b1--aluv) |
| `rtl/alu_controller.v` | 67 | ✅ | **Done 23 Aug** — `JALR` → `` `ADD_C ``. See [B2](#b2--alu_controllerv) |
| `rtl/branch_logic.v` | 35 | ✅ | **Done 23 Aug** — EX-stage resolve, lints clean, 5/5 directed cases |
| `rtl/branch_predictor.v` | 125 | ✅ | **Done 22 Aug** — gshare, lints to 1 benign warning. See [B3](#b3--branch_predictorv) |
| `rtl/register_file.v` | 43 | ✅ | **Done 22 Aug** — 32 regs, `x0` hardwired, cocotb 100/100. See [B4](#b4--register_filev) |
| `rtl/forwarding_unit.v` | 40 | ✅ | **Done 22 Aug** — lints clean. See [B5](#b5--forwarding_unitv) |
| `rtl/instruction_decoder.v` | 100 | ✅ | **Done 22 Aug** — decode verified, suite still to write. See [B6](#b6--instruction_decoderv) |
| `rtl/l1.v` | 894 | ✅ | 4-way cache + WB FIFO + arbiter. Standalone TB exists. **Byte-only data path — cannot do `LW`**, see [Day 4](#day-4--tuesday-cache-integration-p2) |
| `rtl/control.v` | 94 | ✅ | **Started 22 Aug** — opcode decode only; no SYSTEM arm yet |
| `rtl/pc_controller.v` | 38 | ✅ | **Done 23 Aug** — priority encoder, lints clean. See [PC redirect priority](#pc-redirect-priority) |
| `rtl/inst_mem.v` | 0 | — | **empty** |
| `rtl/data_mem.v` | 0 | — | **empty** |
| `rtl/hazard_detector.v` | 0 | — | **empty** |
| `rtl/IF_ID_reg.v` | 0 | — | **empty** |
| `rtl/ID_EX_reg.v` | 14 | ❌ | stub, port list incomplete |
| `rtl/EX_MEM_reg.v` | 0 | — | **empty** |
| `rtl/MEM_WB_reg.v` | 0 | — | **empty** |

**Committed through `6c91be6` ("added control unit").** Note that cocotb build artifacts are tracked — `__pycache__/`, `sim_build/`, `*.vcd`, `results.xml` — so every simulation run dirties the tree. Worth a `.gitignore` + `git rm --cached` before the diffs start mattering for debugging.

---

## The paper's build order — and why to follow it

The paper's whole thesis is *incremental*: each stage is a complete, working processor before the next feature lands.

```
RV32I37F      single-cycle, 37 instrs (no ECALL/EBREAK/FENCE)
    ↓         + CSR file, Zicsr
RV32I43F      single-cycle + CSR access
    ↓         + Trap Controller, Exception Detector, MRET, ECALL, EBREAK
RV32I46F      single-cycle + traps
    ↓         + pipeline regs, Hazard Unit, forwarding, 2-bit predictor
RV32I46F_5SP  5-stage pipelined  ← the target
```

**Do not skip to the pipeline.** A single-cycle core that executes real programs is your oracle: when the pipeline produces a wrong register value on Sunday night, you diff its architectural state against the single-cycle core running the same binary and find the exact instruction where they diverge. Without that oracle you are debugging a pipeline by staring at waveforms, which is how this project misses Tuesday.

The one deviation I'd make from the paper's order: **do the pipeline before CSR/traps.** The pipeline is the risky, schedule-threatening part and it's the headline feature. CSRs are mostly a register file with side effects and can be added to a working pipeline in an evening. That's why P1 sits after P0 in the table above.

---

## How the daily tasks are ranked

Every task below carries two badges, and within each day the tasks are **ordered easiest first**.

| Difficulty | Meaning |
|---|---|
| `★☆☆` | Mechanical. Minutes. No design decision to make. |
| `★★☆` | Moderate. An hour or two. Needs care, but the shape is known. |
| `★★★` | Hard. Half a day or more. This is where the bugs live. |

| Importance | Meaning |
|---|---|
| `P0` | Blocks everything downstream. The day fails without it. |
| `P1` | Required for paper parity. |
| `P2` | Optional. First to go — see [If you fall behind](#if-you-fall-behind). |

Start each day at the top and work down: the cheap items build momentum and, more usefully, they shrink the surface area you're debugging when you hit the hard one. Where a **⚠** appears, the item's position is forced by a dependency rather than by difficulty — you cannot do it earlier even though it is easy.

---

## Day 0 — Saturday morning, unblock (~3 h)

- [ ] `★☆☆ P0` **Stop tracking build artifacts.** Every simulation run currently dirties the tree, which will bury the real diffs exactly when you need them for debugging.
  ```bash
  printf '.venv/\n.claude/\n*.vcd\n*.fst\nsim_build/\n__pycache__/\nresults.xml\nlogfile.txt\n' > .gitignore
  git rm -r --cached tb/cocotb/register_file/{__pycache__,sim_build} \
                     tb/cocotb/register_file/{register_file_dump.vcd,results.xml,logfile.txt}
  git commit -m "Stop tracking cocotb build artifacts"
  ```
- [ ] `★☆☆ P1` **Commit after each module.** Small commits are your bisect trail. When the pipeline misbehaves on Sunday, `git bisect` against the single-cycle core is the fastest way to find the change that did it.
- [ ] `★★☆ P0` **Build the regression harness now, not later.** One command you run after every change:
  ```bash
  # scripts/lint.sh — must stay clean all weekend
  # -Irtl is REQUIRED: modules `include "riscv_defs.vh" (see D5)
  verilator --lint-only -Wall -Irtl --top-module <mod> rtl/<mod>.v
  iverilog -g2001 -I rtl -o /dev/null rtl/<mod>.v
  ```
  Add a `Makefile` at the root with `make lint`, `make test` (runs every cocotb suite), `make wave`. A 30-minute investment that pays back by Sunday afternoon. Any cocotb Makefile for a module that includes the header needs `VERILOG_INCLUDE_DIRS` set, or the build fails with `Include file riscv_defs.vh not found`.
- [ ] `★★☆ P0` **Get a RISC-V toolchain.** Needed to produce test programs; without it you are hand-assembling hex by Sunday.
  ```bash
  sudo apt install gcc-riscv64-unknown-elf   # then use -march=rv32i -mabi=ilp32
  ```
  **Highest-variance item on this list** — it is either five minutes or a two-hour rabbit hole. Timebox it. If the Debian package will not target rv32i cleanly, fall back to `pip install riscv-assembler` for small hand-written tests and defer the real toolchain to S2, when Dhrystone actually needs it. Do not let this block the harness above.

**Done 22 Aug:**

- [x] ~~`★★☆ P0` **Fix `alu.v` and `alu_controller.v`**~~ — [B1](#b1--aluv), [B2](#b2--alu_controllerv). Both compile under `-g2001` and `-g2012`; `alu.v` lints clean under `verilator -Wall`.
- [x] ~~`★★★ P0` **Fix `branch_predictor.v`**~~ — [B3](#b3--branch_predictorv). All 7 syntax defects closed, plus the PHT index mismatch that would have stopped it learning at all.
- [x] ~~`★☆☆ P0` **Fix the widths**~~ — [B4](#b4--register_filev), [B5](#b5--forwarding_unitv). Both at `ADDR_WIDTH = 5`, `x0` hardwired and verified by cocotb.
- [x] ~~`★★☆ P1` **Extract shared constants**~~ — [D5](#d5-shared-constants). 51 duplicated localparams collapsed into `rtl/riscv_defs.vh`.

**Exit criteria:** `make lint` is clean across all of `rtl/`, every non-empty module compiles, cocotb passes on `register_file`.

| Suite | State | Covers |
|---|---|---|
| `tb/cocotb/register_file` | ✅ 100 random, passing | read/write, `x0` hardwiring |
| `tb/tb_ctrl.v`, `tb/tb_l1.v` | ✅ directed | L1 write-back path, FIFO-full drain |
| `tb/cocotb/instruction_decoder` | ❌ **to write** | every format's immediate, shift-imm `funct_7`, the LOAD/SYSTEM funct_3 collision |
| `tb/cocotb/alu` | ❌ **to write** | all 16 ops, signed compares, `SRA` sign-fill, shamt masking, `` `ADD_C `` bit-0 clear |

**Cases the decoder suite must cover** — the decode fix on 22 Aug was verified against these, so they are known to discriminate:

- `SRAI` vs `SRLI` at the same funct_3 — `funct_7[5]` must reach the ALU controller
- `LH`, `LHU`, `CSRRW`, `CSRRWI` — funct_3 001/101 collides with the shifts, and their 12-bit immediates must not truncate to a 5-bit shamt
- `ADDI` at −2048 and +2047 — sign-extension boundaries
- S/B/J immediates at their extremes, since the bit-scrambling in those formats is where transcription errors hide

**Cases the ALU suite must cover** — verified against these on 23 Aug:

- `` `ADD_C `` with an odd sum (masked), an already-even sum (unchanged), and a negative immediate — this is the `JALR` target path
- `SRA` vs `SRL` on a negative operand — sign-fill vs zero-fill
- `LT` vs `LTU` on `0xFFFFFFFF` — signed says less-than, unsigned says not

### Testbench gotchas — learned the hard way on `register_file`, 22 Aug

Reusable for every cocotb monitor you write from here (core, cache, predictor):

- **Sample combinational outputs mid-cycle, not after the clock edge.** `await RisingEdge(clk)` then `await ReadOnly()` lands in the *postponed* region, after NBA updates and any combinational re-evaluation they trigger. For a combinational read off a memory that gets written on that same edge, this shows you the post-write value — which no real consumer sees, because a pipeline register doing `q <= d` samples in the active region and gets the pre-write value. Use `FallingEdge(clk)` + `ReadOnly()` instead. This cost an hour and produced 22 phantom mismatches.
- **`always @(*)` on `mem[addr]` is sensitive to the whole array**, not just `addr`. That is why the write is visible to the read in the same timestep at all.
- **Waves belong in the Makefile, not the RTL.** `WAVES ?= 1` makes cocotb build its own dump module and write FST to `sim_build/`. `$dumpfile` in an RTL module collides as soon as a second testbench opens its own file, and only one can win.
- **A golden model that reads-then-writes is correct for this design.** Don't reorder it to chase a mismatch — check the sampling point first.
- **Compute expectations from the spec, not from the RTL.** The decoder suite re-derives every immediate from the RV32I encoding rules. Mirroring the RTL's own expression would make a wrong implementation agree with a wrong expectation.
- **Mutation-test any suite you're relying on.** Re-introduce the bug it was written to catch, in a scratch copy of the RTL, and confirm it fails. Done for the 22 Aug decode fix: reverting the shift-immediate guard produced exactly 4 failures — `SRAI` ×2, `LH`, `CSRRW`. A suite that cannot fail is worse than no suite, because it buys false confidence.

---

## Day 1 — Saturday, single-cycle RV32I37F

### The memory-interface decision (do this once, get it right)

Define the core↔memory contract **now**, in its final stalling form, even though today's memory is a single-cycle RAM that never stalls:

```verilog
// core drives:  req_valid, req_write, req_addr, req_wdata, req_funct3
// memory drives: req_ready, resp_valid, resp_rdata
// core must hold the request stable while (req_valid && !req_ready)
//
// req_funct3 carries the RV32I load/store funct3 verbatim: [1:0] is the width
// (00 byte, 01 half, 10 word) and [2] selects zero-extension on loads. The
// memory owns sub-word selection and sign/zero-extension -- see D6.
```

Today, tie `req_ready = 1` and `resp_valid = 1` in a trivial `$readmemh` RAM that decodes `req_funct3` itself. On Tuesday the cache slots in behind the same contract — its `cpu_ready_out` / `cpu_data_out_valid` ports already speak the handshake half of this protocol, so the pipeline's stall logic is written and tested by then. **If you skip this and hardwire single-cycle memory, P2 costs you a full day instead of an evening.**

The cache does *not* drop in unchanged, though: it has no size input and a byte-only data path, so it needs the work described at the top of [Day 4](#day-4--tuesday-cache-integration-p2) before it can serve a single `LW`. What the interface decision buys you is that the *pipeline* needs no surgery — the change is confined to the memory.

### PC redirect priority

There is no "which target" select signal, and it cannot come from the decoder. Each candidate target
arrives paired with its own qualifier, and the three redirect sources originate in **three different
pipeline stages** — so no single decode signal could pick between them:

| Qualifier | Target | Originates in |
|---|---|---|
| `trapped` | `t_target` | Trap Controller (Day 3) |
| `bp_miss` | `branch_target_actual` | `branch_logic.v`, EX |
| `ex_jump` | `jump_target` (ALU result) | EX |
| `pc_stall` | hold `if_pc` | Hazard Unit |
| `bp_taken` | `branch_target` | Branch Predictor, IF |
| — | `if_pc + 4` | default |

```verilog
if      (trapped)  pc_next = t_target;                              // 1
else if (bp_miss)  pc_next = branch_target_actual;                  // 2
else if (ex_jump)  pc_next = jump_target;                           // 3  already masked by `ADD_C
else if (pc_stall) pc_next = if_pc;                                 // 4  hold
else if (bp_taken) pc_next = branch_target;                         // 5  speculative
else               pc_next = if_pc + 4;                             // 6
```

The ordering carries real content:

- **Traps win outright.** A trap belongs to an older instruction than anything in EX, and exceptions must be precise — the trapping instruction and everything younger is squashed regardless of what the branch unit thinks.
- **Redirects beat stalls, and this is the one people invert.** If EX mispredicts while a load-use stall is asserted, the instructions held in IF/ID are on the wrong path and about to be flushed anyway. Put `pc_stall` above `bp_miss` and a mispredict gets swallowed by a stall — a hang or silently wrong execution, with no test that obviously catches it.
- **Speculation is last.** `bp_taken` is a guess about the instruction being fetched right now; it loses to any resolved fact about an older instruction.

`bp_miss` and `ex_jump` are mutually exclusive in practice, so their relative order is free — but both must sit above `pc_stall`.

**Note `pc_controller` takes `if_pc`, not `pc+4`.** The separate `PCplus4` path feeds the *pipeline*
(`IF/ID.PC+4` → … → the link writeback at `mem_to_reg = 2'd2`). `pc_controller` does its own `+4` for
the sequential case. Two adders, two consumers — don't share them.

### Tasks

- [ ] `★☆☆ P2` Delete or use `control.v`'s now-unused `DATA_WIDTH`/`REG_WIDTH` parameters
- [x] ~~`★☆☆ P0` `rtl/pc_controller.v`~~ — **done 23 Aug.** Priority encoder over the redirect qualifiers, see [PC redirect priority](#pc-redirect-priority). Pure muxing, no state, lints clean. The `JALR` bit-0 mask moved into the ALU as `` `ADD_C `` ([D8](#d8-where-the-jalr-bit-0-mask-lives)), so this module does no arithmetic beyond `+4`.
- [ ] `★★☆ P0` `rtl/control.v` — finish it. Started 22 Aug; R/I/S/B/J/U arms decode, compiles and lints.
  - [ ] `★☆☆ P1` `funct3` — **settled 22 Aug ([D6](#d6-where-sub-word-access-decodes)): `control.v` keeps only control bits; raw `funct3` rides the pipeline to MEM and the memory decodes it.** So the only remaining consumer here is the SYSTEM arm below. Note `alu_controller.v` already decodes all six branch funct3 values, so the branch decision is just `branch && alu_r[0]` — the control unit never needed funct3 for that.
  - [ ] `★★☆ P1` `` `I_TYPE_1 `` (SYSTEM) arm — `csr_write`, plus the `trap_done`/`csr_ready` inputs, which stay unread until it exists. Can slip to Day 3 with the rest of the CSR work.
- [ ] `★★☆ P0` `rtl/imem.v`, `rtl/dmem.v` — `$readmemh`-loaded, behind the stalling interface above. Fiddlier than it looks: `dmem` needs byte strobes for `SB`/`SH` and sign/zero-extension for `LB`/`LH`/`LBU`/`LHU`.
- [ ] `★★☆ P0` **⚠** `tb/cocotb/core_single/` — self-checking harness: load a `.hex`, run N cycles, assert final register and memory state. Position forced: you want this ready *before* the datapath, so the first thing you do with `core_single.v` is run a program through it rather than stare at waves.
- [ ] `★★★ P0` `rtl/core_single.v` — top-level datapath wiring it all together. The hard one, and the one everything else today exists to support.

### Test programs to write today (`tests/asm/`)

Each is ~10 instructions and ends by writing a known value to a known address:

1. `arith.S` — every R-type op, checked against expected results
2. `imm.S` — every I-type op, **including `ADDI` with a negative immediate** (catches [B2](#b2--alu_controllerv)'s `funct_7` bug)
3. `shift.S` — `SLLI`/`SRLI`/`SRAI` and register-shift forms, shift amounts > 31 masked to 5 bits
4. `ldst.S` — all six load/store widths, aligned, including negative values through `LB`/`LH`
5. `branch.S` — all six branches, taken and not-taken, forward and backward
6. `jump.S` — `JAL`/`JALR`, verify link register and `JALR` LSB clearing
7. `lui_auipc.S` — `LUI` and `AUIPC` (**`AUIPC` will fail until you fix [B6](#b6--instruction_decoderv)**)

**Exit criteria (end of Saturday):** all 7 programs pass on the single-cycle core. This is the checkpoint that decides whether Tuesday is realistic — if you're not here by Saturday night, cut P2 (cache) immediately and protect P0.

---

## Day 2 — Sunday, the 5-stage pipeline (RV32I46F_5SP)

The riskiest day. Budget the whole day; do not add CSRs today no matter how well it's going.

- [ ] `★☆☆ P0` **Register file write-first behaviour** — [B4](#b4--register_filev), the one item still open on that module. Reads are combinational as of 22 Aug, but a WB write landing at the end of cycle N is still invisible to an ID read *during* cycle N, and forwarding only covers producers one and two instructions ahead, so a distance-3 RAW reads stale. Fix: write on `negedge clk`. One word, and it is independent of everything else today — do it first and forget it.
  - **The `register_file` cocotb suite cannot catch this.** It samples mid-cycle, before the write edge, which is exactly the behaviour that hides the bug. `hazard.S` is what has to catch it — make sure that test includes a dependency at **distance 3**, not just 1 and 2.
- [ ] `★★☆ P0` **Pipeline registers first, hazards second.** Insert `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` with no forwarding and no hazard logic. Verify with a test where every instruction is separated by 4 `NOP`s — all 7 Day-1 programs must pass in NOP-padded form. This isolates "did I wire the pipeline right" from "did I get hazards right", and that separation is what keeps Sunday from becoming an undebuggable mess.
- [ ] `★☆☆ P0` **⚠** **Wire in `rtl/forwarding_unit.v`** — already written, lint-clean, and logically correct (EX/MEM priority over MEM/WB is right). Just connect it and drop the NOP padding from the arithmetic tests. Easy, but it cannot happen before the pipeline registers exist.
- [ ] `★☆☆ P0` **⚠** **Wire in `rtl/branch_logic.v`** — written 23 Aug, lints clean, 5/5 directed cases pass. Easy, but it needs `EX_pc`/`EX_imm` out of `ID/EX`, so the pipeline registers must exist first. See [Branch resolution in EX](#branch-resolution-in-ex) for what it needs from the pipeline registers.
- [ ] `★★☆ P0` **Static prediction.** Tie `branch_prediction = 0` (predict not-taken), resolve in EX, flush on `prediction_miss`. Get the pipeline *correct* before making it *fast* — the dynamic predictor is a Monday feature and can only change performance, never correctness. If it changes correctness, your flush logic is broken. With `branch_logic` already in place, switching to the real predictor on Monday is just changing what drives `branch_prediction`.
- [ ] `★★☆ P0` **⚠** Re-run all 7 test programs **unpadded**, then add `hazard.S`: back-to-back dependent ALU ops, load-immediately-followed-by-use, branch on a just-computed value, store of a just-loaded value, and a **distance-3 dependency** for the write-first path above. Last by dependency, not difficulty.
- [ ] `★★★ P0` `rtl/hazard_detector.v` — the empty file, and the hardest thing you will write this weekend. Two jobs:
  - **Load-use stall:** `ID/EX.MemRead && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)` → stall IF/ID, bubble ID/EX. Forwarding cannot fix this one; the data does not exist yet.
  - **Control flush:** on a taken or mispredicted branch resolved in EX, flush `IF/ID` and `ID/EX`.

### Branch resolution in EX

`rtl/branch_logic.v` is the paper's **Branch Logic** block (Fig. 2), resolving branches in EX:

```
in:  branch, EX_pc, EX_imm, alu_cond, branch_prediction
out: prediction_miss, branch_target_actual, branch_taken
```

Three things to hold onto when wiring it:

- **`branch_target_actual` is the *recovery* target, not "the branch target".** It is `EX_pc + 4` by default and `EX_pc + EX_imm` only when actually taken, which is what `pc_controller` needs in **both** mispredict directions. A design that only produces `pc + imm` has no way back when it predicted taken and the branch wasn't.
- **`alu_cond` is not the paper's `ALUzero`.** The paper's ALU subtracts and Branch Logic combines `ALUzero` with `funct3`; yours computes the condition directly (`` `EQ ``/`` `NEQ ``/`` `LT ``/`` `LTU ``/`` `GTE ``/`` `GTEU ``), so `alu_cond` is `alu_r[0]` and is already the taken decision. Same wire position in the diagram, different meaning.
- **`EX_pc` must be the branch's own PC**, carried in `ID/EX` — not the fetch PC. Wiring `IF.PC` here produces silently wrong targets that look like a predictor bug.

`prediction_miss` drives the flush; `branch_taken` trains the predictor (the paper's `EX.BTaken`); `branch` itself is the update enable (`EX.branch`).

**Exit criteria:** all Day-1 programs pass unpadded on the pipelined core, and its final architectural state matches the single-cycle core cycle-for-cycle at retirement.

---

## Day 3 — Monday, predictor + CSRs + traps

### Morning: the dynamic predictor

**This recommendation changed on 22 Aug.** The original plan was to write a throwaway 2-bit PHT and defer gshare to S3, because `rtl/branch_predictor.v` didn't compile and its recovery path looked unsound. Both concerns are gone — it compiles, lints to one benign warning, the index bug that would have stopped it learning is fixed, and the BHR recovery turned out to be correct ([B3](#b3--branch_predictorv)). **Use the gshare predictor. Don't write the simple one.**

What's left here is integration, not the predictor itself:

- [ ] `★☆☆ P0` **⚠** **Gate `history_read` on a fetch-word pre-decode** — decided 23 Aug from Fig. 2 ([B3](#b3--branch_predictorv)): `history_read = (inst[6:2] == `B_TYPE)`. Not optional; `branch_logic.v` cannot recover from a prediction made on a non-branch. Everything below depends on it.
- [ ] `★☆☆ P1` Extract the B-type immediate in IF for `B_Target` — the paper's predictor computes the target itself from `IF.PC`/`IF.imm`; yours doesn't, so either `pc_controller` does `PC + imm` or the predictor gains the port. Pure bit-shuffling of the fetch word, no decode needed.
- [ ] `★☆☆ P1` Carry `{prediction_out, prediction_index, bhr_snap_index}` through `IF/ID` and `ID/EX` — 9 + `$clog2(BHR_SNAPS)` bits per in-flight branch. Widening two registers.
- [ ] `★★☆ P1` Wire the prediction port into IF and the update port into branch resolution in EX
- [ ] `★★☆ P1` On mispredict in EX: flush, and assert `history_write` with `predicted_index`/`predicted_in`/`predicted_snap_index` taken from the pipeline registers
- [ ] `★★☆ P1` Verify it *predicts*: a loop of 100 iterations should mispredict ~2 times, not ~100. Count mispredicts in the TB and assert on the number.
- [ ] `★★☆ P1` Verify it *trains*: a consistently-taken branch should reach `2'b11`, and an alternating branch should settle. This is the test that would have caught the index bug — a predictor that never learns still produces correct results, so only a test like this can tell you it is working.

**Fallback:** if predictor integration is still fighting you by Monday lunchtime, fall back to static predict-not-taken and move to CSRs. The predictor only affects CPI, never correctness — if it changes a program's result, your flush logic is wrong, not your predictor.

### Afternoon: Zicsr → RV32I43F

- [ ] `★☆☆ P1` CSR writes are a hazard source too — a CSR read in ID after a CSR write in EX needs forwarding or a stall. Under deadline the simplest correct answer is **stall**.
- [ ] `★★☆ P1` `rtl/csr_file.v` — at minimum `mstatus`, `mtvec`, `mepc`, `mcause`, `mie`, `mip`, and **`mcycle`/`minstret`** (you need those two for the DMIPS measurement in S2)
- [ ] `★★☆ P1` `CSRRW`/`CSRRS`/`CSRRC` plus the immediate forms, decoded from `` `I_TYPE_1 `` (`op_code = 1110011`). Needs [B6](#b6--instruction_decoderv) item 3 — the decoder does not extract the `csr`/`zimm` fields yet.

### Evening: traps → RV32I46F

- [ ] `★★☆ P1` `rtl/exception_detector.v` — illegal instruction, misaligned load/store, misaligned instruction address, `ECALL`, `EBREAK`
- [ ] `★★☆ P1` `trap.S` — trigger `ECALL`, land in a handler at `mtvec`, `MRET` back, verify execution resumes at `mepc+4`
- [ ] `★★★ P1` `rtl/trap_controller.v` — on trap: save `PC`→`mepc`, cause→`mcause`, jump to `mtvec`, flush the pipeline; `MRET` restores. Hard because it is a second control-flow override racing the branch flush you built on Sunday — get the priority between them right.

**Exit criteria:** paper feature-parity for the core. **This is the point where you can legitimately say the project is done.** Everything after is bonus.

---

## Day 4 — Tuesday, cache integration (P2)

Only start this if Monday's exit criteria are met and committed on a tag.

- [ ] `★☆☆ P0` `git tag rv32i46f-5sp-verified` — a known-good point to return to. Do this before touching anything.
- [ ] `★★★ P2` **⚠ BLOCKER — sub-word access in the cache.** Position forced and it is the hardest item of the day: nothing below can proceed until this is done, because the cache cannot currently service an `LW`. As written, `rtl/l1.v` is **byte-only**:
  - `l1.v:848` reads one byte and zero-extends it — that is exactly `LBU`, and there is no path that returns a full word
  - `l1.v:857` writes one byte — that is exactly `SB`
  - Needed: a size/signedness input on **both** `cache` and `cache_controller` (the outer CPU port has no such signal at all), a read path that selects byte/half/word by `byte_index_r` and sign- **or** zero-extends, and a byte-enable read-modify-write covering 1, 2 or 4 bytes
  - **Re-read the P2 decision in light of this.** It is materially more work than "wire the cache in", and [If you fall behind](#if-you-fall-behind) already puts P2 first on the chopping block.
- [ ] `★☆☆ P2` **⚠** Re-run the **entire** test suite after wiring. A cache is a correctness-neutral optimisation: if any test changes result, the cache or the stall path is wrong, not the test. Trivial to run, last by dependency.
- [ ] `★★☆ P2` Build a backing-memory model with realistic latency (`mem_ready` deasserted for N cycles) — `tb/tb_ctrl.v` already has the shape of one to borrow
- [ ] `★★☆ P2` Wire `cache_controller` from `rtl/l1.v` in as the **data** memory only. Leave instruction fetch on the simple RAM — one variable at a time.
- [ ] `★★☆ P2` Pipeline must stall on `!cpu_ready_out` and wait for `cpu_data_out_valid`. Your Day-1 interface decision makes this a hazard-unit change, not a datapath change.
- [ ] `★★★ P2` Only then consider the instruction side. Two independent stall sources into the same pipeline is materially harder than one.

**Risk:** the cache's `BLOCK_BITS = 512` block against a 32-bit core means a miss moves 64 bytes. Make sure the miss path and the write-back FIFO drain logic are exercised — `tb/tb_ctrl.v` covers FIFO-full drain, which is the nastiest case, so that TB is worth trusting.

---

## Stretch — after Tuesday

**S1 — FPGA bring-up.** Vendor-neutral core, vendor-specific edges:
- Replace `$readmemh` init with your toolchain's memory-init flow
- Memory inference: your `(* ramstyle = ... *)` attributes are correct Intel syntax, so they'll be honoured by Quartus. Read the fitter report rather than trusting the attributes — in particular check whether `pht` (128 × 2 bits) actually landed in an M9K, and whether spending a 9,216-bit block on 256 bits of state is what you want versus `"MLAB"`. The paper's 3,010 LUT / 998 FF figure is Artix-7 and won't transfer; expect different numbers on Cyclone.
- Clock: start at 25 MHz, not 50. Meet timing, then push.
- Then UART TX → GPIO (LEDs + buttons) → the clock-enable single-step debug feature the paper describes.

**S2 — Dhrystone 2.1.** Needs the full toolchain, `-O2`, a working `mcycle`/`minstret`, and UART output. Paper's number: 646,640 instructions in 1,043,092 cycles = 1.09 DMIPS/MHz, 1.61 CPI.

**S4 — jump prediction.** Per [D7](#d7-jump-prediction), jumps currently eat the full EX-resolution
penalty. Redirecting `JAL` in ID halves that; a BTB for `JALR` is the larger version. Measure the CPI
delta against the D7 baseline rather than assuming it.

**S3 — predictor comparison.** gshare is now the Day 3 design rather than a stretch goal. The stretch version is the *measurement*: build the plain 2-bit PHT (`pht[pc[8:2]]`, no BHR — about 20 lines) as a drop-in alternative and compare mispredict counts and CPI on the same benchmarks. Quantifying what the BHR buys you is the most publishable thing here, and it goes beyond what the paper reports.

---

## Bug list from the audit

### B1 — `alu.v`

**✅ Resolved 22 Aug.** Rewritten and fixed. For the record, what was wrong and what closed it:

| | Original issue | Resolution |
|---|---|---|
| 1 | Trailing comma in port list; no `;` after port list | fixed in your rewrite |
| 2 | `localparam SLL = 4'd6` missing `;` | fixed 22 Aug |
| 3 | `input alu_op` 1 bit vs 4-bit opcodes | now `[3:0]` |
| 4 | `output r` assigned in `always` | now `output reg` |
| 5 | `$signed(x < y)` — signed compare was actually unsigned | now `($signed(x) < $signed(y))` |
| 6 | `SRA` was a logical shift | now `$signed(x) >>> y[4:0]` |
| 7 | Shifts used all 32 bits of `y` | all three now mask `y[4:0]` |
| 8 | No `default` → inferred latch | `r = 0` default assignment **and** a `default:` arm |
| 9 | `EQ` / `NEQ` returned inverted results — `BEQ`/`BNE` would branch backwards | fixed 22 Aug |
| 10 | Missing `parameter` keyword broke Verilog-2001 | fixed 22 Aug |

**Design note for Day 2.** The op set grew past the paper's: `EQ`, `NEQ`, `GTE`, `GTEU`, `LT`, `LTU` mean the ALU now performs the *branch comparison itself*, and `PC` (`x + 4`) produces the link value for `JAL`/`JALR`. That's a good simplification — the EX stage has no separate comparator, the branch decision is just the ALU result — but it has two consequences to design around:

- The branch unit in EX reads `r[0]` as its taken/not-taken signal. Wire it that way from the start.
- `PC` needs the *PC* on the `x` input, not `rs1`. Your EX-stage `x` mux must be able to select PC, and forwarding must **not** override it. Get this wrong and `JAL` links to a forwarded register value.

**Update 23 Aug — `` `ADD_C `` added, `` `PC `` retired.** `JALR` needs `(rs1+imm)` with bit 0 cleared, and that mask now lives in the ALU rather than in `pc_controller` ([D8](#d8-where-the-jalr-bit-0-mask-lives)). Since jumps moved to `` `ADD ``/`` `ADD_C ``, the old `` `PC `` op (`x + 4`) had no remaining producer, so `ADD_C` took its encoding slot and **`alu_op` stayed 4 bits** — no extra bit through `ID/EX`.

The field is now exactly full: 16 ops at values 0–15. A 17th op means widening the port in two modules and the pipeline register, so it is worth a moment's thought rather than a reflex.

Nothing outstanding in this file.

### B2 — `alu_controller.v`

**✅ Syntax resolved 22 Aug; 2 TODOs left in-file.** Rewritten as a `casez` over `{op_code[6:2], funct_7[5], funct_3}`, which is a better structure than the original `funct_3`-only case — it decodes R-type, I-type, loads, stores, branches and jumps in one table, and correctly ignores `funct_7[5]` for `ADDI` while honouring it for `SRAI`. That closes the original bug where `ADDI x1, x2, -2048` decoded as a subtract.

| | Original issue | Resolution |
|---|---|---|
| 1 | Missing `,` after `funct_3`; `SLL` localparam missing `;` | fixed |
| 2 | `output alu_op` assigned in `always` | now `output reg [3:0]` |
| 3 | Case items were decimal (`010` = ten), so most ops fell through | replaced by the `casez` table |
| 4 | `op_code` never read → `ADDI` with a negative immediate subtracted | `op_code[6:2]` is now part of the case expression |
| 5 | Only R-type funct3 handled | loads/stores/`LUI`/`JAL`/branches all covered |
| 6 | No `default` → latch | `alu_op = NON` default assignment + `default:` arm |
| 7 | `3'b00` — 2-bit literal in a 3-bit field, zero-padded to `000`, so `SLLI` decoded as `ADD` | fixed 22 Aug → `3'b001` |
| 8 | `defualt` typo parsed as a case *item*, not the default arm | fixed 22 Aug |
| 9 | `JALR` never matched — only `J_TYPE` (JAL) was on the `PC` arm, so `JALR` returned 0 as its link value | fixed 22 Aug, `I_TYPE_2` added |

**✅ Both TODOs closed 22 Aug:**

- **`AUIPC` now decodes.** `U_TYPE` was split into `` `U_TYPE_1 `` (LUI, `5'b01101`) and `` `U_TYPE_2 `` (AUIPC, `5'b00101`) in [`riscv_defs.vh`](#d5-shared-constants); both map to `` `ADD ``, and [B6](#b6--instruction_decoderv) gained a matching arm, so it works end to end.
- **`NOP_TYPE` is gone**, collapsed onto `` `I_TYPE_3 `` when the constants moved to the shared header — same value, and the LOAD→`ADD` mapping stays correct.

**Update 23 Aug.** `` `J_TYPE `` stays on the `` `ADD `` arm — a `JAL` target is inherently even, so it needs no mask — while `` `I_TYPE_2 `` (`JALR`) moved to its own `` `ADD_C `` arm. Port narrowed back to `[3:0]` alongside [B1](#b1--aluv).

**Benign lint warnings** (don't chase these): `funct_7[6,4:0]` and `op_code[1:0]` are legitimately never needed; `I_TYPE_1` (SYSTEM) goes live on Day 3 with CSRs; `DATA_WIDTH` is an unused parameter you can delete.

### B3 — `branch_predictor.v`

**✅ Resolved 22 Aug.** A gshare predictor (BHR XOR PC index, with BHR snapshots for misprediction recovery) — more ambitious than the paper's plain 2-bit PHT. Now compiles under `-g2001` and `-g2012` and lints to a single benign warning.

| | Original issue | Resolution |
|---|---|---|
| 1 | `localparam LOCATIONS` missing `;` | fixed |
| 2 | `bhr_snaps` declaration missing `;` | fixed |
| 3 | `predicted_read` / `pht_read` assigned but never declared | removed |
| 4 | `prediction_out` / `prediction_valid` were wires but driven in an `always` | now `output reg` |
| 5 | `pht[predicted_inde_r]` typo | fixed |
| 6 | `current_index` was 1 bit | now `[HIST_BITS-1:0]` |
| 7 | PHT reset block had no `else`, so resets were overwritten in the same block | `else` added |
| 8 | Missing `parameter` keyword broke Verilog-2001 | fixed 22 Aug |
| 9 | **Predict and update indexed different address spaces.** Read used `bhr ^ pc[8:2]`; update truncated a 32-bit PC to `pc[6:0]` with no XOR. Every update trained the wrong entry, so the predictor could never learn. | fixed 22 Aug — new registered `prediction_index` output carries the actual index through the pipeline and back on `predicted_index` |
| 10 | Dead `snap_index` reg | removed |
| 11 | Mixed sync/async reset across the two always blocks (`SYNCASYNCNET`) | unified to async |
| 12 | PHT initialised to `2'b00`, so every branch mispredicted twice before it could predict taken | now `2'b01` |

**Two things that look like bugs but are correct** — comment them before you forget, or you'll "fix" them into breakage:

- **BHR recovery.** L54 snapshots the *post-shift* value `{bhr[5:0], pred}`; L59 recovers with `{snap[6:1], actual}`. Since `snap[6:1] == bhr[5:0]`, that reconstructs the pre-shift history and appends the true outcome. The two apparent off-by-ones cancel exactly.
- **Snapshot index handshake.** L54 writes `bhr_snaps[bhr_snap_index]` before L55 increments, so latching `{prediction_out, prediction_index, bhr_snap_index}` in the same cycle yields a matched set.

**Still open:**

- **`history_read` gating — ✅ settled 23 Aug from Fig. 2: gate on a pre-decode of the fetch word.** The paper's Branch Predictor takes **`IF.opcode`** as an input, so it only predicts on actual branches and the BHR is never polluted by non-branches. Implement as `history_read = (inst[6:2] == `B_TYPE)` in IF.
  - **This is now a correctness requirement, not a preference.** [`branch_logic.v`](#branch-resolution-in-ex) reports `prediction_miss = 0` whenever `branch` is low. If an ungated predictor redirects the PC for a non-branch, that instruction reaches EX with `branch = 0`, nothing flushes, and execution continues from the wrong address with no recovery path.
- **The predictor does not compute `B_Target`; the paper's does.** Fig. 2 shows the Branch Predictor taking `IF.PC` and `IF.imm` and emitting `B_Target` alongside `B.EST`. Yours emits only `prediction_out`/`prediction_index`, so either `pc_controller.v` computes `PC + imm` itself or you add it here. Either way you need the **B-type immediate extracted in IF**, before the decoder runs — pure bit-shuffling of the fetch word (`{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}`), no decode required, but it is logic that does not exist yet.
- **Naming:** `predicted_valid` (input) vs `prediction_valid` (output) differ by one character and appear in the same expressions. Rename the input to `update_valid`.
- **Residual one-cycle skew** (won't fix): `current_index` uses `bhr` from the cycle before `prediction_valid` rises, while the snapshot uses `bhr` from the cycle after. Now that the index is carried separately this no longer affects PHT training — it only slightly degrades recovery fidelity.
- **Pipeline cost:** each in-flight branch must now carry 7 bits of `prediction_index` plus 2 bits of `prediction_out` plus `$clog2(BHR_SNAPS)` bits of snapshot index. Size `IF/ID` and `ID/EX` accordingly.

### B4 — `register_file.v`

**✅ Three of four resolved 22 Aug.** Verified by the cocotb suite at 100/100.

| | Issue | Resolution |
|---|---|---|
| 1 | `ADDR_WIDTH = 3` → 8 registers; RV32I has 32 | now `ADDR_WIDTH = 5` |
| 2 | `x0` was a normal writable register, so `addi x0,x0,0` (the canonical NOP) corrupted the zero constant | writes to addr 0 dropped, reads of addr 0 forced to zero |
| 3 | Registered read with no write-first bypass | read is now combinational; **bypass still outstanding**, see Day 2 |
| 4 | `$dumpfile`/`$dumpvars` inside the RTL | removed; waves now come from `WAVES ?= 1` in the cocotb Makefile, written to `sim_build/register_file.fst` |

Two changes made along the way that aren't in the original defect list:

- **`file <= 0` in the reset branch didn't elaborate** — you can't assign a scalar to an unpacked array in Verilog-2001, and iverilog doesn't support it in `-g2012` either. The array now has no reset at all and takes its power-up state from an `initial` loop, which is what `ramstyle = "logic"` wants: distributed RAM has no reset port, and forcing one would infer 1,024 flip-flops instead.
- **The `reset` port is gone**, since nothing used it any more.

**Read style is settled: combinational read, `ID/EX` registers the operands.** This is the conventional structure and matches the paper's diagram. The consequence to hold onto is that the register file is now a plain memory, *not* a memory plus a pipeline stage — so `ID/EX` must latch `read_data_1/2`, and there is no hidden extra cycle in the operand path.

### B5 — `forwarding_unit.v`

**✅ Resolved 22 Aug.** `ADDR_WIDTH = 5`, `parameter` keyword added, lints clean at `-Wall`. The logic was always correct: EX/MEM is tested before MEM/WB, which is the right priority for the double-hazard case, and both paths suppress forwarding from `x0`.

One gap for Day 2: a `SW` whose store-data comes from an immediately preceding `LW` needs a MEM→MEM forward this unit doesn't provide. Add `mem_forward` once loads and stores are both working.

Note the division of labour with [B4](#b4--register_filev) — this unit's `RD != 0` checks stop a stale *forward* of `x0`, but they never stopped a write to `x0` landing in the file. That required the register file's own hardwiring. Two separate guards; both are needed.

### B6 — `instruction_decoder.v`

| | Issue | Status |
|---|---|---|
| 1 | **`AUIPC` was missing** — `U_TYPE = 5'b01101` covered `LUI` only | ✅ **Fixed 22 Aug.** Split into `` `U_TYPE_1 `` (LUI) and `` `U_TYPE_2 `` (AUIPC, `5'b00101`), each with its own arm. Both use the same U-format immediate `{inst[31:12], 12'b0}`, so the two arms are identical and could merge |
| 2 | **The I-type arm never set `funct_7`**, so `SRAI` was indistinguishable from `SRLI` | ✅ **Fixed 22 Aug.** Shift immediates now take `funct_7 = inst_in[31:25]` and a 5-bit shamt. The guard is `inst_in[6:2] == `I_TYPE_4`, which matters: that case arm also covers LOAD and SYSTEM, whose funct_3 of 001/101 (`LH`, `LHU`, `CSRRW`, `CSRRWI`) would otherwise have their immediates truncated to 5 bits |
| 3 | `` `I_TYPE_1 `` (SYSTEM) needs the `csr`/`zimm` fields | ❌ Open — add on Day 3 with CSRs |

---

## Open decisions

### D1. Immediate generation

**✅ Settled 22 Aug — `immediate_generator.v` deleted.** `instruction_decoder.v` already generates every immediate format correctly, so the separate module was redundant. This is a deliberate deviation from the paper, which lists them as separate modules under design principle #2 ("clear module roles") — note it in the README.

### D2. Branch resolution stage
The paper resolves in EX and flushes 2 stages. Resolving in ID would cost only 1 flush cycle but adds a comparator and more forwarding paths in ID. **Stay with EX** — it matches the paper, and the dynamic predictor is what recovers the CPI anyway.

### D5. Shared constants

**✅ Settled 22 Aug — `rtl/riscv_defs.vh`.** The 16 ALU op codes were duplicated between `alu.v` and `alu_controller.v`, and the instruction classes between `alu_controller.v` and `instruction_decoder.v` — 51 duplicated `localparam` lines. All of it now lives in one guarded header, referenced as `` `ADD ``, `` `R_TYPE `` and so on.

Consequences to remember:

- **Every build needs the include path.** `-I rtl` for iverilog, `-Irtl` for verilator, `VERILOG_INCLUDE_DIRS` for cocotb. Without it: `Include file riscv_defs.vh not found`.
- **Macros are one global namespace** for the whole compilation, not per-module. `` `ADD ``, `` `OR ``, `` `EQ `` are now reserved project-wide. If third-party or vendor sources ever collide, the escape hatch is a prefix (`` `RV_ADD ``).
- **Some lint signal was lost.** Verilator used to warn that `I_TYPE_1` was an unused localparam, which was a live reminder that SYSTEM wasn't decoded. Macros aren't tracked that way, so that warning is gone — `alu_controller.v` went 5 → 3 warnings without anything being fixed.
- `` `AUIPC_TYPE `` was briefly defined and then superseded by `` `U_TYPE_2 ``. Don't reintroduce it.

### D6. Where sub-word access decodes

**✅ Settled 22 Aug — the memory decodes it, not the control unit.** `control.v` emits control bits only; raw `funct3` is carried through `ID/EX` and `EX/MEM` to the MEM stage, and `dmem.v` (Day 1) / the cache (Day 4) do the width selection and sign/zero-extension.

Why it holds up:

- Keeps `control.v` to one job, matching the paper's design principle #2
- `funct3` in the pipeline is not single-use — the Day 3 `exception_detector` needs the access width to detect misaligned loads and stores, and it will already be there
- Costs the same 3 pipeline-register bits as sending decoded `mem_size`/`mem_unsigned` would have

What it costs:

- **`dmem.v` and the cache both implement it.** Loads are P0 and the cache is P2, so the logic gets written twice — two implementations of one interface contract, not waste, but budget for it.
- **The cache is nowhere near ready for this.** See the blocker at the top of [Day 4](#day-4--tuesday-cache-integration-p2).

### D8. Where the `JALR` bit-0 mask lives

**✅ Settled 23 Aug — in the ALU, as `` `ADD_C ``.** The spec requires the `JALR` target to be
`(rs1 + imm)` with bit 0 forced to zero. Two places could do it: `pc_controller` masking the target on
the jump path, or a dedicated ALU op.

The ALU won because it keeps `pc_controller` a pure mux with no arithmetic beyond `+4`, and because the
masked value is then what every consumer sees rather than only the PC path. `JAL` stays on plain
`` `ADD ``, since a J-format immediate always has bit 0 clear.

It cost nothing in width: `` `PC `` (`x + 4`) became dead when jumps moved to the ALU for target
calculation, so `` `ADD_C `` took its slot and `alu_op` stayed 4 bits. See [B1](#b1--aluv).

### D7. Jump prediction

**✅ Settled 23 Aug — jumps are not predicted; accept the EX-resolution penalty.** The predictor gates
`history_read` on `` `B_TYPE `` ([B3](#b3--branch_predictorv)), so `JAL`/`JALR` always resolve in EX and
cost the full ~2-cycle bubble. This matches the paper and keeps the redirect path single-sourced.

Revisit only once the full pipeline is working. A `JAL` target is computable in ID (it needs no
register), so redirecting there costs 1 bubble instead of 2 — but it adds a second redirect source and
another priority tier to [PC redirect priority](#pc-redirect-priority), which is not a thing to be
debugging alongside the hazard unit.

### D3. `x0` handling location
Hardwire in the register file (B4-2) rather than special-casing in the control path. One place, impossible to forget.

---

## Definition of done

- [ ] Every module lints clean under `verilator -Wall`
- [ ] All test programs pass on the 5-stage core, unpadded
- [ ] Pipelined core's retired architectural state matches the single-cycle core on every test
- [ ] Branch predictor demonstrably reduces mispredicts on a loop benchmark
- [ ] `ECALL` → handler → `MRET` round-trips correctly
- [ ] Cache integration leaves every test result unchanged
- [ ] `README.md` documents the deviations from the paper (D1, and gshare-vs-2-bit)
- [ ] Clean commit history with a tag at `rv32i46f-5sp-verified`

---

## If you fall behind

Cut in this order — protect the working core above all:

1. **Cut P2 (cache).** It isn't in the paper. Nothing about paper-parity depends on it.
2. **Cut the dynamic predictor**, keep static predict-not-taken. Correctness is unaffected; you lose only CPI.
3. **Cut traps**, keep Zicsr. `RV32I43F` is still a legitimate milestone in the paper's own progression.
4. **Cut the pipeline.** `RV32I46F` single-cycle with CSRs and traps is a complete, working, honestly-describable RISC-V processor. A finished single-cycle core beats a half-debugged pipeline every time.
