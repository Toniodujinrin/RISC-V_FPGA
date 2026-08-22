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
| `rtl/alu.v` | 57 | ✅ | **Done 22 Aug** — lints clean under `-Wall`. See [B1](#b1--aluv) |
| `rtl/alu_controller.v` | 100 | ✅ | **Done 22 Aug** — 2 TODOs left in-file. See [B2](#b2--alu_controllerv) |
| `rtl/branch_predictor.v` | 124 | ✅ | **Done 22 Aug** — gshare, lints to 1 benign warning. See [B3](#b3--branch_predictorv) |
| `rtl/register_file.v` | 45 | ✅ | **Done 22 Aug** — 32 regs, `x0` hardwired, cocotb 100/100. See [B4](#b4--register_filev) |
| `rtl/forwarding_unit.v` | 40 | ✅ | **Done 22 Aug** — lints clean. See [B5](#b5--forwarding_unitv) |
| `rtl/instruction_decoder.v` | 89 | ✅ | Missing AUIPC + shift-imm `funct_7`. See [B6](#b6--instruction_decoderv) |
| `rtl/l1.v` | 894 | ✅ | 4-way cache + WB FIFO + arbiter. Standalone TB exists |
| `rtl/control.v` | 0 | — | **empty** |
| `rtl/pc_controller.v` | 0 | — | **empty** |
| `rtl/hazard_detector.v` | 0 | — | **empty** |

**There are zero commits in this repo.** First action of Day 0 is `git commit`. You are about to do heavy refactoring with no undo.

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

## Day 0 — Saturday morning, unblock (~3 h)

- [ ] **`git init` is done but nothing is committed.** Commit the current tree as-is, right now, before touching anything.
  ```bash
  printf '.venv/\n*.vcd\nsim_build/\n__pycache__/\nresults.xml\n' > .gitignore
  git add -A && git commit -m "Initial import: partial RV32I modules, L1 cache, TBs"
  ```
- [ ] **Get a RISC-V toolchain.** You need it to produce test programs; without it you're hand-assembling hex by Sunday.
  ```bash
  sudo apt install gcc-riscv64-unknown-elf   # then use -march=rv32i -mabi=ilp32
  ```
  If the Debian package won't target rv32i cleanly, fall back to `pip install riscv-assembler` for small hand-written tests, and defer the full toolchain to S2 when Dhrystone actually needs it.
- [ ] **Build a regression harness now, not later.** One script you run after every change:
  ```bash
  # scripts/lint.sh — must stay clean all weekend
  verilator --lint-only -Wall --top-module <mod> rtl/<mod>.v
  ```
  Add a `Makefile` at the root with `make lint`, `make test` (runs every cocotb suite), `make wave`. A 30-minute investment that pays back by Sunday afternoon.
- [x] ~~**Fix `alu.v` and `alu_controller.v`**~~ — [B1](#b1--aluv), [B2](#b2--alu_controllerv) done 22 Aug. Both compile under `-g2001` and `-g2012`; `alu.v` lints clean under `verilator -Wall`.
- [x] ~~**Fix `branch_predictor.v`**~~ — [B3](#b3--branch_predictorv) done 22 Aug. All 7 syntax defects closed, plus the PHT index mismatch that would have stopped it learning at all.
- [x] ~~**Fix the widths**~~ — [B4](#b4--register_filev), [B5](#b5--forwarding_unitv) done 22 Aug. Both at `ADDR_WIDTH = 5`, both lint clean, `x0` hardwired and verified by cocotb.
- [ ] Commit after each module. Small commits are your bisect trail.

**Exit criteria:** `make lint` is clean across all of `rtl/`, every non-empty module compiles, cocotb passes on `register_file` and `alu`.

### Testbench gotchas — learned the hard way on `register_file`, 22 Aug

Reusable for every cocotb monitor you write from here (core, cache, predictor):

- **Sample combinational outputs mid-cycle, not after the clock edge.** `await RisingEdge(clk)` then `await ReadOnly()` lands in the *postponed* region, after NBA updates and any combinational re-evaluation they trigger. For a combinational read off a memory that gets written on that same edge, this shows you the post-write value — which no real consumer sees, because a pipeline register doing `q <= d` samples in the active region and gets the pre-write value. Use `FallingEdge(clk)` + `ReadOnly()` instead. This cost an hour and produced 22 phantom mismatches.
- **`always @(*)` on `mem[addr]` is sensitive to the whole array**, not just `addr`. That is why the write is visible to the read in the same timestep at all.
- **Waves belong in the Makefile, not the RTL.** `WAVES ?= 1` makes cocotb build its own dump module and write FST to `sim_build/`. `$dumpfile` in an RTL module collides as soon as a second testbench opens its own file, and only one can win.
- **A golden model that reads-then-writes is correct for this design.** Don't reorder it to chase a mismatch — check the sampling point first.

---

## Day 1 — Saturday, single-cycle RV32I37F

### The memory-interface decision (do this once, get it right)

Define the core↔memory contract **now**, in its final stalling form, even though today's memory is a single-cycle RAM that never stalls:

```verilog
// core drives:  req_valid, req_write, req_addr, req_wdata, req_wstrb
// memory drives: req_ready, resp_valid, resp_rdata
// core must hold the request stable while (req_valid && !req_ready)
```

Today, tie `req_ready = 1` and `resp_valid = 1` in a trivial `$readmemh` RAM. On Tuesday, `rtl/l1.v` drops in unchanged (its `cpu_ready_out` / `cpu_data_out_valid` ports already speak this protocol) and the pipeline's stall logic is already written and tested. **If you skip this and hardwire single-cycle memory, P2 costs you a full day instead of an evening.**

### Tasks

- [ ] `rtl/control.v` — main decode: `RegWrite`, `MemRead`, `MemWrite`, `MemToReg`, `ALUSrc`, `Branch`, `Jump`, `ALUOp`. Drive from `op_code` only.
- [x] ~~`rtl/alu_controller.v` — extend past R-type~~ — done 22 Aug. Loads/stores/`LUI`/`JAL`/`JALR` map to `ADD`/`PC`, all six branches map to compare ops. **`AUIPC` still missing** (TODO in-file).
- [ ] `rtl/pc_controller.v` — `pc+4`, branch target, `JAL` target, `JALR` target (**remember to clear bit 0**)
- [ ] `rtl/imem.v`, `rtl/dmem.v` — `$readmemh`-loaded, behind the interface above. `dmem` needs byte strobes for `SB`/`SH` and sign/zero-extension for `LB`/`LH`/`LBU`/`LHU`.
- [ ] `rtl/core_single.v` — top-level datapath wiring it all together
- [ ] `tb/cocotb/core_single/` — self-checking: load a `.hex`, run N cycles, assert final register/memory state

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

- [ ] **Pipeline registers first, hazards second.** Insert `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` with no forwarding and no hazard logic. Verify with a test where every instruction is separated by 4 `NOP`s — all 7 Day-1 programs must pass in NOP-padded form. This isolates "did I wire the pipeline right" from "did I get hazards right".
- [ ] **`rtl/forwarding_unit.v`** — already written and logically correct (EX/MEM priority over MEM/WB is right). Just needs the width fix. Wire it in, remove the NOP padding from the arithmetic tests.
- [ ] **`rtl/hazard_detector.v`** — the empty file. Two jobs:
  - **Load-use stall:** `ID/EX.MemRead && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)` → stall IF/ID, bubble ID/EX. Forwarding cannot fix this one; the data doesn't exist yet.
  - **Control flush:** on a taken/mispredicted branch resolved in EX, flush `IF/ID` and `ID/EX`.
- [ ] **Register file write-first behaviour** — [B4](#b4--register_filev), the one item still open on that module. Reads are combinational as of 22 Aug, but a WB write landing at the end of cycle N is still invisible to an ID read *during* cycle N, and forwarding only covers producers one and two instructions ahead. A distance-3 RAW therefore reads stale. Fix: write on `negedge clk`.
  - **The `register_file` cocotb suite cannot catch this.** It samples mid-cycle, before the write edge, which is exactly the behaviour that hides the bug. `hazard.S` is what has to catch it — make sure that test includes a dependency at distance 3, not just 1 and 2.
- [ ] **Static prediction first.** Predict not-taken, resolve in EX, flush on mispredict. Get the pipeline *correct* before making it *fast* — the dynamic predictor is a Monday feature and it can only change performance, never correctness. If it changes correctness, your flush logic is broken.
- [ ] Re-run all 7 test programs **unpadded**. Add `hazard.S`: back-to-back dependent ALU ops, load-immediately-followed-by-use, branch on a just-computed value, store of a just-loaded value.

**Exit criteria:** all Day-1 programs pass unpadded on the pipelined core, and its final architectural state matches the single-cycle core cycle-for-cycle at retirement.

---

## Day 3 — Monday, predictor + CSRs + traps

### Morning: the dynamic predictor

**This recommendation changed on 22 Aug.** The original plan was to write a throwaway 2-bit PHT and defer gshare to S3, because `rtl/branch_predictor.v` didn't compile and its recovery path looked unsound. Both concerns are gone — it compiles, lints to one benign warning, the index bug that would have stopped it learning is fixed, and the BHR recovery turned out to be correct ([B3](#b3--branch_predictorv)). **Use the gshare predictor. Don't write the simple one.**

What's left here is integration, not the predictor itself:

- [ ] **Decide the `history_read` gating question first** ([B3](#b3--branch_predictorv), "still open"). Everything below depends on it.
- [ ] Wire the prediction port into IF; wire the update port to branch resolution in EX
- [ ] Carry `{prediction_out, prediction_index, bhr_snap_index}` through `IF/ID` and `ID/EX` — that's 9 + `$clog2(BHR_SNAPS)` bits per in-flight branch
- [ ] On mispredict in EX: flush, assert `history_write` with `predicted_index`/`predicted_in`/`predicted_snap_index` from the pipeline registers
- [ ] Verify: a loop of 100 iterations should mispredict ~2 times, not ~100. Count mispredicts in the TB and assert on the number.
- [ ] Verify the PHT actually trains: a branch that alternates taken/not-taken should settle, and a consistently-taken branch should reach `2'b11`. This is the test that would have caught the index bug.

**Fallback:** if predictor integration is still fighting you by Monday lunchtime, fall back to static predict-not-taken and move to CSRs. The predictor only affects CPI, never correctness — if it changes a program's result, your flush logic is wrong, not your predictor.

### Afternoon: Zicsr → RV32I43F

- [ ] `rtl/csr_file.v` — at minimum `mstatus`, `mtvec`, `mepc`, `mcause`, `mie`, `mip`, and **`mcycle`/`minstret`** (you need these two for the DMIPS measurement in S2)
- [ ] `CSRRW`/`CSRRS`/`CSRRC` + immediate forms, decoded from `I_TYPE_1` (`op_code = 1110011`)
- [ ] CSR writes are a hazard source too — a CSR read in ID after a CSR write in EX needs forwarding or a stall. Simplest correct answer under deadline: **stall**.

### Evening: traps → RV32I46F

- [ ] `rtl/exception_detector.v` — illegal instruction, misaligned load/store, misaligned instruction address, `ECALL`, `EBREAK`
- [ ] `rtl/trap_controller.v` — on trap: save `PC`→`mepc`, cause→`mcause`, jump to `mtvec`, flush the pipeline. `MRET` restores.
- [ ] Test: `trap.S` — trigger `ECALL`, land in a handler at `mtvec`, `MRET` back, verify execution continues at `mepc+4`.

**Exit criteria:** paper feature-parity for the core. **This is the point where you can legitimately say the project is done.** Everything after is bonus.

---

## Day 4 — Tuesday, cache integration (P2)

Only start this if Monday's exit criteria are met and committed on a tag.

- [ ] `git tag rv32i46f-5sp-verified` — a known-good point to return to
- [ ] Wire `cache_controller` from `rtl/l1.v` in as the **data** memory only. Leave instruction fetch on the simple RAM. One variable at a time.
- [ ] Pipeline must stall on `!cpu_ready_out` and wait for `cpu_data_out_valid`. Your Day-1 interface decision means this is a hazard-unit change, not a datapath change.
- [ ] You need a backing-memory model with realistic latency (`mem_ready` deasserted for N cycles) — `tb/tb_ctrl.v` already has the shape of one to borrow.
- [ ] Re-run the **entire** test suite. A cache is a correctness-neutral optimisation: if any test changes result, the cache or the stall path is wrong.
- [ ] Only then consider the instruction side.

**Risk:** the cache's `BLOCK_BITS = 512` block against a 32-bit core means a miss moves 64 bytes. Make sure the miss path and the write-back FIFO drain logic are exercised — `tb/tb_ctrl.v` covers FIFO-full drain, which is the nastiest case, so that TB is worth trusting.

---

## Stretch — after Tuesday

**S1 — FPGA bring-up.** Vendor-neutral core, vendor-specific edges:
- Replace `$readmemh` init with your toolchain's memory-init flow
- Memory inference: your `(* ramstyle = ... *)` attributes are correct Intel syntax, so they'll be honoured by Quartus. Read the fitter report rather than trusting the attributes — in particular check whether `pht` (128 × 2 bits) actually landed in an M9K, and whether spending a 9,216-bit block on 256 bits of state is what you want versus `"MLAB"`. The paper's 3,010 LUT / 998 FF figure is Artix-7 and won't transfer; expect different numbers on Cyclone.
- Clock: start at 25 MHz, not 50. Meet timing, then push.
- Then UART TX → GPIO (LEDs + buttons) → the clock-enable single-step debug feature the paper describes.

**S2 — Dhrystone 2.1.** Needs the full toolchain, `-O2`, a working `mcycle`/`minstret`, and UART output. Paper's number: 646,640 instructions in 1,043,092 cycles = 1.09 DMIPS/MHz, 1.61 CPI.

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

**Still open (TODOs are written at the bottom of the file):**

- **`AUIPC` is not decoded.** `op_code[6:2] == 5'b00101` has no localparam; it falls to `default → NON`. Needs fixing here *and* in [B6](#b6--instruction_decoderv) before `AUIPC` works end to end. Your `lui_auipc.S` test on Day 1 is what will catch this.
- **`NOP_TYPE` is misnamed** — the value `5'b00000` is the LOAD opcode, duplicating the unused `I_TYPE_3`. Mapping it to `ADD` is correct for load address calculation; only the name is wrong.

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

- **`history_read` gating — decide before Day 2 wiring.** The BHR shifts on every fetch where `history_read` is asserted, but at IF you don't yet know the instruction is a branch. Either gate `history_read` with a pre-decode of the fetch word, or accept history pollution from non-branches. This is an integration decision, not a code fix, and it applies to any BHR-based design.
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
| | Issue | Fix |
|---|---|---|
| 1 | **`AUIPC` is missing.** `U_TYPE = 5'b01101` is `LUI` only; `AUIPC` is `inst[6:2] = 5'b00101`. `AUIPC` currently decodes to all-zeros. **`alu_controller.v` has the identical gap** — fix both together. | add the opcode |
| 2 | The I-type branch never sets `funct_7`, so `SRAI` is indistinguishable from `SRLI`. | set `funct_7 = inst_in[31:25]` on the I-type path |
| 3 | `I_TYPE_1` (SYSTEM) needs the `csr`/`zimm` fields for Day 3 | add when you do CSRs |

---

## Open decisions

### D1. Immediate generation

**✅ Settled 22 Aug — `immediate_generator.v` deleted.** `instruction_decoder.v` already generates every immediate format correctly, so the separate module was redundant. This is a deliberate deviation from the paper, which lists them as separate modules under design principle #2 ("clear module roles") — note it in the README.

### D2. Branch resolution stage
The paper resolves in EX and flushes 2 stages. Resolving in ID would cost only 1 flush cycle but adds a comparator and more forwarding paths in ID. **Stay with EX** — it matches the paper, and the dynamic predictor is what recovers the CPI anyway.

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
