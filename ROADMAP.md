# BASIC_RV32s Implementation Roadmap

Reproducing **RV32I46F_5SP** from *BASIC_RV32s: An Open-Source Microarchitectural Roadmap for RISC-V RV32I* (Kang & Choi, ISOCC 2025) — `2510.15887v1.pdf`.

- **Start:** Sat 22 Aug 2026
- **Target:** Sun 23 Aug (core done) → ~~hard deadline Tue 25 Aug~~ → **deadline now Sun 30 Aug**
  (moved from Fri 28th). The day-by-day structure below is kept as the record of how the work was
  sequenced; the live schedule is [marathon § Time budget](marathon.md#time-budget-vs-reality).
- **Toolchain present:** `iverilog`, `verilator`, `gtkwave`, `cocotb` 2.0.1 (in `.venv`), **RISC-V binutils/GCC (27 Aug)**
- **Toolchain missing:** FPGA vendor tools only — see [Day 0](#day-0--saturday-morning-unblock-3-h)

> **28 Aug — both memories are inside the core.** `inst_mem.v` and `data_mem.v` are written and
> instantiated in `datapath.v`, so neither instruction fetch nor the cache's backing port crosses the
> module boundary any more; only the io bus does. Fetch is a synchronous ROM re-timed against the PC
> ([Instruction fetch](#instruction-fetch-is-a-retimed-synchronous-rom-28-aug)), and the cache is
> backed by a real word-wide memory with a counter-driven block burst
> ([The backing memory](#the-backing-memory-28-aug)). `r_type.s` still passes end to end through both.
>
> **27 Aug — the pipeline executes assembled programs and self-checks against a golden model.**
> `tb/cocotb/datapath` assembles a `.s` with real `as`/`objcopy`, feeds the image to the core through an
> instruction-memory model, and compares retired PC + all 32 registers per instruction against a Python
> ISA model. `r_type.s` (R-type + immediate arithmetic, back-to-back dependencies) passes.
> **This is the oracle the plan kept asking for**, arrived at from the other direction: a golden ISA
> model in Python rather than a single-cycle core in Verilog. See
> [The datapath testbench](#the-datapath-testbench-27-aug).

---

## Scope call (read this first)

The paper covers two halves: **(a)** an incrementally-built pipelined core, **(b)** an SoC with UART + GPIO + Dhrystone synthesised at 50 MHz on Artix-7. Half (a) is achievable by Tuesday. Half (b) — plus the L1 cache integration you want, which is **not in the paper at all** (the paper's memories are plain LUT-based distributed RAM) — is more than 4 days of work if you're also debugging a first-time pipeline.

> **Goal changed 23 Aug: the target is running real GCC-compiled C, not just reproducing the paper.**
> First programs are small — iterative and recursive Fibonacci — then anything that fits in memory.
> This is a *reordering*, not just an addition. See [Running C](#running-c--what-it-actually-needs).

So this plan commits to a **primary target** and treats the rest as sequenced stretch:

| | Deliverable | When |
|---|---|---|
| **P0** | RV32I 5-stage pipelined core, forwarding + hazard unit, passing self-checking sim tests | **by Mon 24** |
| **P0** | **GCC-compiled C running in sim** — toolchain + `crt0.S` + linker script + simple RAM, `fib.c` as the first target | **Mon 24** |
| **P1** | Dynamic predictor wired in (CPI only, never correctness) | **Mon 24** |
| **P1** | Zicsr + trap/exception handling (`RV32I43F` → `RV32I46F`) | ~~Tue 25~~ **Sun 30, or cut** |
| **P2** | `rtl/l1.v` wired in as the core's memory, core stalls on miss | ✅ **done 28 Aug** |
| **S1** | FPGA synthesis + UART SoC on your board | ~~after Tue~~ **Sun 30, or cut** |
| **S2** | Dhrystone 2.1 + DMIPS/MHz measurement | cut — does not fit |

> **Rescheduled 28 Aug for the Sunday deadline.** ~23–25 h remain against a ~57 h backlog, so the two
> P1/S1 rows above are **mutually exclusive**: there is room for the core deliverable plus *one* of
> Zicsr+traps or the board, not both. The choice, and the argument on each side, is in
> [marathon § Time budget](marathon.md#time-budget-vs-reality) — decide it Saturday evening once the
> `.s` suite and the C ladder are actually green.

**What the goal change displaces.** Running C needs a correct pipeline, working `LW`/`SW`, a toolchain,
and startup code. It does **not** need traps, CSRs, or the branch predictor — so Zicsr/traps drop behind
"C runs".

> **Revised 23 Aug: the cache is the memory from the start.** The byte-only blocker is gone — `l1.v`
> now services word, half and byte (see [Sub-word access](#sub-word-access-in-the-cache-resolved)), so
> the plain-RAM intermediate step buys less than it used to and costs a second memory interface to
> write and throw away. Two things that follow from this and are easy to miss:
>
> - **You still need a backing memory behind the cache.** `l1.v`'s memory port is block-wide
>   (`BLOCK_BITS = 512`) with a `mem_ready`/`mem_data_in_valid` handshake. `inst_mem.v`/`data_mem.v`
>   do not disappear — they become that backing store. `tb/tb_ctrl.v` already has a model to borrow.
> - **Debug cost is the real trade.** A cache miss stall is live from the first pipeline bring-up, so a
>   wrong result could be the pipeline *or* the stall path. Mitigate by keeping instruction fetch on a
>   simple ROM at first and putting only the data side through the cache — two independent stall
>   sources into one pipeline is materially harder than one, and that ordering costs you nothing.

The one design decision that makes P2 cheap is in [Day 1](#the-memory-interface-decision-do-this-once-get-it-right): **give the core a `valid`/`ready` stalling memory interface from the very first single-cycle version.** Then on Tuesday the cache swaps in behind an interface the pipeline already respects, instead of being surgery on a finished design.

> **Target board: Intel Cyclone, Quartus toolchain.** The existing `(* ramstyle = ... *)` attributes are already correct Intel syntax and stay as-is. This differs from the paper's Xilinx Artix-7, so expect different resource numbers and a different UART primitive in S1. Everything before S1 is vendor-neutral.

---

## Running C — what it actually needs

Beyond a correct RV32I core, GCC output needs seven things. Three are now built; the list below says
which, because the ordering only makes sense once you know what is left.

1. **`LW`/`SW` must work.** The ABI spills registers on every non-leaf call — recursive fib is
   `sw ra,12(sp)` / `lw ra,12(sp)` before it is anything else. **Resolved 23 Aug** — `l1.v` now does
   word, half and byte ([Sub-word access](#sub-word-access-in-the-cache-resolved)).
2. **A stack.** `sp` must point at the top of RAM before `main`, and RAM must hold the deepest call
   chain. `fib_rec(20)` is ~20 frames.
3. **`crt0.S` + a linker script.** Nothing currently sets `sp`, sets `gp`, zeroes `.bss`, or calls
   `main`. Minimum: `_start` loads `sp` and `__global_pointer$`, zeroes `.bss`, `call main`, then stores
   to `SIM_EXIT`. Linker script puts `.text` at the reset vector and `.data`/`.bss` in RAM.
4. **libgcc.** With `-march=rv32i` GCC emits calls to `__mulsi3`, `__divsi3`, `__udivsi3`, `__modsi3`
   for `*`, `/`, `%`. They live in libgcc, so link it (`-lgcc`). No hardware change needed — an
   unresolved-symbol error here is the usual first surprise. Hardware M is an optimisation, not a
   requirement.
5. **Sub-word access.** `char`/`short` need `LB/LBU/LH/LHU/SB/SH` — see [D6](#d6-where-sub-word-access-decodes).
6. **Somewhere for output to go.** **Resolved 30 Aug** — `SIM_EXIT` and a real UART behind an APB
   bridge, see [Memory-mapped IO](#memory-mapped-io).
7. **A way to get `.data`/`.rodata` into RAM.** This one was missing from the original list and it is
   the one that actually blocks the ladder at step 2. The split is Harvard: the core has **no data path
   to instruction memory**, so the usual trick — `crt0` copying `.data` from a load address in ROM to
   its run address in RAM — *cannot work here*. Initialised data has to be placed directly into
   `data_mem`. **Resolved 30 Aug**: `data_mem.v` takes a `DATA_FILE` and `$readmemb`s it over a zeroed
   array (so `.bss` is ready with no work), and `load_memories()` pokes `dut.D_MEM.mem` the same way it
   already pokes imem. `test_data_init` proves the path end to end — RAM preloaded, read back through
   the cache, compared in the program.

> **All seven closed 30 Aug — GCC-compiled C runs.** `tb/cocotb/c_test/` holds `asm/crt0.s`,
> `link.ld` and `c_ctb.py`; `test_fib_iter` and `test_sum` both pass. Items 2, 3 and 4 were the last
> three and were entirely software: `crt0.s` sets `gp` and `sp`, clears `.bss`, calls `main` and stores
> the return value to `SIM_EXIT`; `link.ld` gives imem and RAM separate `MEMORY` regions; the build
> links `-lgcc` and runs objcopy **twice**, `.text` to the imem image and `.rodata` + `.data` to the
> dmem image.
>
> Two things that made the difference between a passing test and a vacuous one, worth remembering when
> adding rungs: at `-O2` gcc folds a `const` array's sum at compile time and never touches memory, so
> `sum.c` marks it `volatile` to force the loads; and the loader zero-fills RAM, so a `.bss` global
> reads as 0 whether or not `crt0` cleared it — `run_c` poisons RAM past the data image with
> `0xDEADBEEF` so the clear loop is the only thing that can make it zero.

### The C ladder

`tests/c/`, in dependency order — each step adds exactly one new requirement:

| program | first needs |
|---|---|
| `fib_iter.c` — loop, no calls | registers + branches only; runs before memory works at all — ✅ **30 Aug** |
| `sum.c` — sum a global array | `.data` init, `LW`, `gp` — ✅ **30 Aug**, covers `.rodata`, `.data` and a cleared `.bss` |
| `fib_rec.c` — recursive | stack, `sp`, `jal`/`jalr`, spill/reload |
| `strlen.c` / struct walk | `LB`/`LBU`, `SB` |
| `divmod.c` | libgcc soft mul/div |
| `hello.c` | MMIO UART + `putchar` — the UART is built, but `putchar` must enable it and poll `TX_EMPTY` |

Check results by storing the pass/fail code to `SIM_EXIT` and reading it back in the TB. Do not depend
on `printf` until `hello.c` — a failing `printf` and a failing core look identical.

> **The test mode for this exists as of 30 Aug.** `run_to_exit(dut, settings, data_words=())` in
> `datapth_ctb.py` assembles, loads both memories, runs until `exit_valid` and returns `exit_code` —
> no golden model and no scoreboard, because a golden model of GCC output is not worth building when
> the program checks itself. `test_exit_check` and `test_data_init` use it. A C test is the same call
> with `gcc` in place of `as` in `assemble()`, and `data_words` from the second objcopy.

## Memory-mapped IO

**The thing to get right: MMIO must bypass the cache.** Decode the address in MEM *before* routing the
request, and send IO down a separate path. If MMIO goes through `l1.v`, UART writes sit in the
write-back FIFO instead of appearing, and a status-register read returns a stale cached value forever —
so a `while(!(UART_STATUS & 1));` poll hangs on the first character.

```
addr[31:28] == 4'hF  ->  IO bus      (uncached, single cycle, word access)
otherwise            ->  RAM / cache
```

> **Built 30 Aug — the map below is the RTL, not the plan.** What was sketched as a flat table of
> word-spaced registers is an APB bridge (`rtl/io_apb_bridge.v`) with a 4K window per slave, wired up in
> `rtl/mmio.v`. The UART's registers are byte wide and byte addressed, so software reaches them with
> `lb`/`sb`, not `lw`/`sw`.

| window | slave |
|---|---|
| `0xF000_0000` – `0xF000_0FFF` | `SIM_EXIT` — answers at every offset in the window |
| `0xF000_1000` – `0xF000_1FFF` | `UART` |

| address | register | |
|---|---|---|
| `0xF000_00FC` | `SIM_EXIT` | write ends the run, value = exit code |
| `0xF000_1000` | `UART_TX_DATA` | write: starts a frame, but only if `TX_ENABLE` and `TX_EMPTY` |
| `0xF000_1001` | `UART_RX_DATA` | read: received byte, and the read consumes `RX_VALID` |
| `0xF000_1002` | `UART_CONTROL` | b0 `PARITY_EN`, b1 `UART_ENABLE`, b2 `RX_ENABLE`, b3 `TX_ENABLE`, b4 `RX_OVERRUN` |
| `0xF000_1003` | `UART_CONFIG` | b1:0 baud index, b4:2 data bits − 1, b6:5 stop bits, b7 parity type. Resets to `0x3D` — 8N1 |
| `0xF000_1004` | `UART_STATUS` | b0 `TX_BUSY`, b1 `RX_BUSY`, b2 `TX_EMPTY`, b3 `RX_VALID`, b4 `PARITY_ERROR`. Read only; a read clears `PARITY_ERROR` |
| `0xF000_1005` | `UART_IRQ` | storage only — there is no interrupt controller upstream |

GPIO is not built. Windows 2 and 3 are unpopulated on purpose: `N_C` is 2, so an access there fails the
bridge's decoder and returns `io_slv_err` instead of hanging. That distinction matters — the bridge's
ACCESS state has no timeout, so a window with nothing in it to drive `PREADY` would wedge the core
permanently on a typo'd address.

`RX_OVERRUN` is in `CONTROL` rather than `STATUS` because it has to be *writable*: hardware sets it when
a frame lands on an unread `RX_DATA`, and it gates the receiver off until software clears it. Clearing
it is a read-modify-write of the whole byte — write `0x0E` back, not `0x00`, or the enables go with it.

- **`SIM_EXIT` first** — ✅ **done 30 Aug**, `rtl/io/sim_exit.v`. A store that ends the run with a
  pass/fail code is what turns every C program into a self-checking test. `FINISH=0` for cocotb, which
  cannot survive an RTL `$finish`: the Makefile passes `-Pdata_path.SIM_EXIT_FINISH=0` and the test
  awaits `exit_valid` itself.
- **The UART is real RTL, not a two-line sim model** (`rtl/io/uart.v`, 30 Aug), so `putchar` has real
  work to do: enable the UART first (`UART_CONTROL` = `0x0E`), then poll `TX_EMPTY` before every byte.
  A write to `TX_DATA` while the transmitter is busy is *refused*, not queued — there is no FIFO.
- `TX_EMPTY` is set out of reset, so the first `putchar` falls straight through; every one after it
  waits a full frame. At the 8N1 default that is 10 bit times, so keep `printf` out of the hot path of
  any test with a cycle budget.
- MMIO reads must not be cached or speculative; MMIO writes must not be buffered or reordered.
- The decoder belongs in MEM, next to the load/store path — **not** inside `l1.v`. Keeping it outside
  means the cache never sees an IO address and needs no changes.

> **Done 25 Aug in `rtl/lsu.v`.** `is_io = em_alu_result[31:28] == IO_PAGE` (parameterised, defaults
> `4'hF`), evaluated on the raw address in the issue cycle, so an IO access is never presented to the
> cache at all. IO shares the LSU's single wait state — `io_access_r` records which port the
> outstanding access used and the response side is a mux — so IO inherits the same issue-once,
> stall-until-response guarantee. `io_req` is a strict one-cycle pulse, which is what stops a UART
> write firing repeatedly while the pipeline is stalled, and IO loads return through the same
> `BE_logic` path so a `char`-typed device register sign-extends correctly. **Slave contract:** sample
> `io_req` for one cycle, return `io_ack` with `io_data_out` alongside it. Nothing answers on the
> other end yet.

---

## Where the code actually stands

Compile-checked with `iverilog -g2012` on 22 Aug:

| File | Lines | Compiles | Status |
|---|---|---|---|
| `rtl/riscv_defs.vh` | 48 | — | 16 ALU ops (4-bit field, **full**) + instruction classes. See [D5](#d5-shared-constants) |
| `rtl/alu.v` | 43 | ✅ | **Done 23 Aug** — `ADD_C` added, `` `PC `` retired, lints clean. See [B1](#b1--aluv) |
| `rtl/alu_controller.v` | 67 | ✅ | **Done 23 Aug** — `JALR` → `` `ADD_C ``. See [B2](#b2--alu_controllerv) |
| `rtl/branch_logic.v` | 35 | ✅ | **Done 23 Aug** — EX-stage resolve, lints clean, 5/5 directed cases |
| `rtl/branch_predictor.v` | 129 | ✅ | **Working 29 Aug.** Written 23 Aug but predicted taken *zero* times until the lookup was made combinational to match the BTB, and the PHT update gated on `predicted_valid`. The skew was a **correctness** bug, not just CPI: it redirected the pc for the wrong instruction. 100-iteration loop now mispredicts 10/100. See [B3](#b3--branch_predictorv) |
| `rtl/btb.v` | 104 | ✅ | **Done 23 Aug** — fully-associative branch target buffer, 4 entries. See [D9](#d9-btb-structure-and-depth) |
| `rtl/register_file.v` | 45 | ✅ | **Done 23 Aug** — 32 regs, `x0` hardwired, write-first. See [B4](#b4--register_filev) |
| `rtl/forwarding_unit.v` | 43 | ✅ | **Done.** `forward_a`/`forward_b` only — the undriven `source_a`/`source_b` ports were dropped, the datapath owns the mux. Instantiated as `FORWARDING_UNIT` and exercised by the smoke test. See [B5](#b5--forwarding_unitv), [D12](#d12-what-gets-forwarded) |
| `rtl/instruction_decoder.v` | 107 | ✅ | **`r_imm` driven 25 Aug** — zero-extended immediate on every arm. Decode verified, suite still to write. See [B6](#b6--instruction_decoderv) |
| `rtl/l1.v` | 916 | ✅ | 4-way cache + WB FIFO + arbiter. **Sub-word access added 23 Aug** — word/half/byte via a new `cpu_size` port. See [Sub-word access](#sub-word-access-in-the-cache-resolved) |
| `rtl/control.v` | 88 | ✅ | **Updated 23 Aug** — `mem_to_reg` widened to 3 bits (5 writeback sources); standalone `lui` output folded in as encoding `011`. No SYSTEM arm yet |
| `rtl/pc_controller.v` | 38 | ✅ | **Done 23 Aug** — priority encoder, lints clean. See [PC redirect priority](#pc-redirect-priority) |
| `rtl/program_counter.v` | 22 | ✅ | **Done 23 Aug** — async-reset PC register |
| `rtl/inst_mem.v` | 34 | ✅ | **Done 28 Aug, `IMEM_DEPTH` 1024 → 8192 on 30 Aug** — 32 KB of code, which C plus libgcc's soft multiply/divide will want. On Cyclone V that is 256 Kbit, ~26 M10K blocks out of the 397 on a 5CSEMA5. Synchronous ROM, `$readmemb` init, range-checked `output_valid`. Re-timed against the PC rather than stalled; see [Instruction fetch](#instruction-fetch-is-a-retimed-synchronous-rom-28-aug) |
| `rtl/data_mem.v` | 120 | ✅ | **Done 28 Aug, `DATA_FILE` init 30 Aug** — word-wide array, counter-driven block burst, latching FSM. Backs the cache. Zeroed then `$readmemb`-ed at time 0, which is the only way `.data`/`.rodata` can reach a Harvard core — see [Running C](#running-c--what-it-actually-needs) item 7. Still 1024 words: `.data` + `.bss` + the stack all live in 4 KB, so watch it once `fib_rec` runs. Verified with `tb/tb_dmem.v`; see [The backing memory](#the-backing-memory-28-aug) |
| `rtl/hazard_detector.v` | 85 | ✅ | **Done 25 Aug** — pure combinational. `req_stall` outranks every redirect; exports `mem_advance` to the LSU. Wired into `datapath.v` |
| `rtl/lsu.v` | 147 | ✅ | **Done 25 Aug, load data fixed 29 Aug** — owns the cache handshake: issue-once, valid held until accepted, combinational `req_stall`, `DONE` state, MMIO bypass. The response is now bypassed around its register on the cycle the stall drops; before that every `lw` wrote back stale data. See [The memory-stall handshake](#the-memory-stall-handshake) |
| `rtl/IF_ID_reg.v` | 74 | ✅ | **Done 23 Aug** — carries the full prediction payload; flush drops it. Verified in sim |
| `rtl/ID_EX_reg.v` | 198 | ✅ | **Done 23 Aug, forwarding capture added 29 Aug** — full control/decode/datapath/prediction payload. Now re-captures the forwarded operands while stalled, or a distance-2 dependency across a memory stall reads a stale register. See [What belongs in a pipeline register](#what-belongs-in-a-pipeline-register), [D12](#d12-what-gets-forwarded) |
| `rtl/EX_MEM_reg.v` | 124 | ✅ | **Done 23 Aug** — `em_` prefix. Completes all four pipeline registers; chain verified in sim |
| `rtl/MEM_WB_reg.v` | 97 | ✅ | **Done 23 Aug** — module renamed `MEM_WB_reg` to match the file. All 5 writeback sources cross. `csr_write` still to add for Day 3 |
| `rtl/BE_logic.v` | 22 | ✅ | **Done 24 Aug** — load sign-extension, the surviving half of the paper's `BE_Logic`. Verified with the cache end to end |
| `rtl/datapath.v` | 700 | ✅ | **Wired 24 Aug, LSU + hazard unit 25 Aug, executing programs 27 Aug, both memories internal 28 Aug.** All five stages plus `LSU`/`HAZARD`; the stall/flush stubs are gone. **`mmio.v` instantiated 30 Aug**, so the `io_*` bus no longer crosses the boundary — only the UART pins, `exit_valid`/`exit_code` and `io_slv_err` do. Runs assembled R-type/I-type programs correctly against a golden model. CSR is still a TODO stub. See [Datapath wiring](#datapath-wiring-24-aug), [The datapath testbench](#the-datapath-testbench-27-aug) |
| `rtl/io_apb_bridge.v` | 172 | ✅ | **Done 30 Aug** — LSU port to APB3 master. Registered `PSEL`/`PENABLE` FSM, 4K-window decoder, `PSTRB` and lane alignment from `io_size` (a `sb` to an odd address lands in the right byte), sub-word reads masked to match what the cache hands `BE_logic`. `io_slv_err` on decode error or `PSLVERR`. **No timeout in `ACCESS`** — every populated window must drive `PREADY` |
| `rtl/mmio.v` | 149 | ✅ | **Done 30 Aug** — the bridge plus its slaves. `N_C = 2`, so windows 2 and 3 fail decode rather than hang. `sim_exit` sits behind a `generate` on `SIM_EXIT_PRESENT`: drop it for the fitter build, the block being simulation only |
| `rtl/io/sim_exit.v` | 77 | ✅ | **Done 30 Aug** — zero wait state, answers at every offset in its window so a stray access returns instead of hanging. `FINISH=0` for cocotb |
| `rtl/io/uart.v` | 619 | ✅ | **Done 30 Aug** — APB slave, `uart_tx`, `uart_rx`, `tick_gen`. Byte-wide register file, configurable 5–8 data bits / 1–2 stop bits / odd-even parity, `RX_OVERRUN` gating the receiver. Loopback-verified through the bridge including a corrupted frame. Its `tick_gen` never ticked at all before 30 Aug — a missing `begin`/`end` put `tick <= 0` outside the `else`, so it overrode the assert every cycle |

**Committed through `f324e45` ("tb passes with r_type").** `.gitignore` landed 27 Aug — but it has a
typo, **`sim_builf` should be `sim_build`**, so every simulation still dirties the tree. It is also
missing `*.vcd`, `*.fst`, `logfile.txt` and `tb/cocotb/*/build/`. Fix that before the diffs start
mattering for debugging.

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

**Do not skip to the pipeline.** A single-cycle core that executes real programs is your oracle: when the pipeline produces a wrong register value, you diff its architectural state against the single-cycle core running the same binary and find the exact instruction where they diverge. Without that oracle you are debugging a pipeline by staring at waveforms, which is how this project misses Tuesday.

> **Superseded 27 Aug — the oracle exists, and it isn't a single-cycle core.** The
> [datapath testbench](#the-datapath-testbench-27-aug) compares the pipeline against a **golden ISA
> model in Python**, per retired instruction, which serves the identical purpose: it names the exact
> instruction where behaviour diverges. It is also strictly cheaper — a Python model costs no RTL, no
> second memory interface and no second thing to keep in sync as the ISA grows. **Do not now write a
> single-cycle core to satisfy this paragraph.** The paper's incremental order still has value as a
> *bring-up* strategy; it is no longer needed as a *debugging* one.

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

- [~] `★☆☆ P0` **Stop tracking build artifacts.** — **partly done 27 Aug.** `.gitignore` exists but
  **`sim_builf` is a typo for `sim_build`**, so simulation output is still tracked; `*.vcd`, `*.fst`,
  `logfile.txt` and `tb/cocotb/*/build/` are missing from it too. Every simulation run currently dirties the tree, which will bury the real diffs exactly when you need them for debugging.
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
- [x] ~~`★★☆ P0` **Get a RISC-V toolchain.**~~ — **done 27 Aug.** `binutils-riscv64-unknown-elf` +
  `gcc-riscv64-unknown-elf` from the Ubuntu archive, at `/usr/bin/riscv64-unknown-elf-*`. The datapath TB
  shells out to `as`/`objcopy` on every run, so this is exercised continuously rather than trusted.
  ```bash
  sudo apt install gcc-riscv64-unknown-elf   # then use -march=rv32i -mabi=ilp32
  ```
  Was **a hard blocker, not a timebox** — as of the 23 Aug goal change the deliverable *is* compiled C,
  so there is no hand-assembly fallback that still reaches the target. It is either five minutes or a
  two-hour rabbit hole; if the Debian package will not target rv32i cleanly, try
  `xpack-dev-tools/riscv-none-elf-gcc` or a prebuilt SiFive toolchain rather than deferring. You need
  `gcc`, `ld`, `objcopy` and **libgcc** — see [Running C](#running-c--what-it-actually-needs) for why
  libgcc matters even without the M extension.

**Done 22 Aug:**

- [x] ~~`★★☆ P0` **Fix `alu.v` and `alu_controller.v`**~~ — [B1](#b1--aluv), [B2](#b2--alu_controllerv). Both compile under `-g2001` and `-g2012`; `alu.v` lints clean under `verilator -Wall`.
- [x] ~~`★★★ P0` **Fix `branch_predictor.v`**~~ — [B3](#b3--branch_predictorv). All 7 syntax defects closed, plus the PHT index mismatch that would have stopped it learning at all.
- [x] ~~`★☆☆ P0` **Fix the widths**~~ — [B4](#b4--register_filev), [B5](#b5--forwarding_unitv). Both at `ADDR_WIDTH = 5`, `x0` hardwired and verified by cocotb.
- [x] ~~`★★☆ P1` **Extract shared constants**~~ — [D5](#d5-shared-constants). 51 duplicated localparams collapsed into `rtl/riscv_defs.vh`.

**Exit criteria:** `make lint` is clean across all of `rtl/`, every non-empty module compiles, cocotb passes on `register_file`.

| Suite | State | Covers |
|---|---|---|
| `tb/cocotb/register_file` | ✅ 100 random, passing | read/write, `x0` hardwiring |
| `tb/cocotb/datapath` | ✅ 5 programs passing | **whole-core, self-checking against a golden ISA model** — see [The datapath testbench](#the-datapath-testbench-27-aug) |
| ↳ `r_type.s` · `b_type.s` | ✅ | R/I arithmetic and every branch, taken and not |
| ↳ `loop.s` | ✅ | **predictor regression** — 100 iterations, asserts the mispredict rate. The only test that catches the prediction skew |
| ↳ `sl_type.s` · `sl_2_type.s` | ✅ | every load/store width and offset, signed and unsigned |
| ↳ `full_type.s` | ✅ | **the only test that catches forwarding loss across a memory stall** — needs a long cache stall *and* a distance-2 dependency across it |
| `tb/tb_ctrl.v`, `tb/tb_l1.v` | ✅ directed | L1 write-back path, FIFO-full drain, sub-word access |
| `tb/tb_dmem.v` | ✅ directed, **new 28 Aug** | `cache_controller` + `data_mem` together: refill, second refill, address wrap, dirty eviction reaching memory |
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

### Instruction fetch is a retimed synchronous ROM (28 Aug)

`inst_mem.v` is a **synchronous** ROM — its read is registered, which is what lets it infer M10K
instead of burning LUTs. That is a one-cycle latency the old async-fetch wiring did not expect.

**A fixed latency is fixed by retiming, not by stalling.** Address the ROM with `if_pc_next` rather
than `if_pc` and its output register sits *in parallel* with the PC register instead of in series
behind it:

```
addressed with if_pc          addressed with if_pc_next
pc_next -[PC]- if_pc -[ROM]-  pc_next -+-[PC ]- if_pc
          1 deep    2 deep             +-[ROM]- imem_data     both 1 deep
```

Both are then one register behind `pc_next`, the skew is zero, and `imem_data` is aligned with
`if_pc` exactly as an async read was — **no stall, no extra pipeline stage, no CPI cost.**

Three things that are easy to get wrong here, all of which cost the instruction at pc 0:

- **`imem_araddr = reset ? 0 : if_pc_next`.** During reset the PC is *held* at 0 while `pc_controller`
  still computes `if_pc + 4`, so the parallel property breaks unless the address is forced to 0.
- **The ROM output register must not be reset.** It has to keep capturing *through* reset so
  `mem[0]` is already present on the first cycle after release — same discipline as `register_file`'s
  array, which takes its power-up state from `initial` and has no reset port.
- **`output_valid` must be 1 coming out of reset**, not 0. Wire it to `IF_ID.instr_valid`; reset it
  low and instruction 0 becomes a bubble.

**A stall (and a second LSU in fetch) is only needed for *variable* latency — i.e. an I-cache.** That
is [E6] in marathon, `★★★ P2`, and cut #3 in triage. `.text` in on-chip ROM is a legitimate design
point, not a compromise. Note the BTB already assumes this future: it exists precisely because the
instruction word will not be available in IF once fetch is cached, so nothing has to change when an
I-cache eventually lands.

**Cost to watch:** `imem_araddr` now depends on `pc_controller` → `btb_target`, so the BTB lookup and
the ROM address decode are in the same cycle. At ~93 MHz that wants checking in the fitter report, not
assuming.

---

### Fetching past the end of the program (28 Aug)

**Do not pad instruction memory with NOPs.** That was a testbench crutch and does not survive a
compiler, real flash, or DDR. Three mechanisms replace it:

1. **A correct program never runs off the end** — `crt0.S` ends in `1: j 1b` or `wfi` ([C2] in
   marathon). Falling through is a fault path, not a state to design memory contents around.
2. **The ISA reserves the escape hatch.** RISC-V defines the all-zero *and* all-ones instruction words
   as illegal **specifically to catch jumps into zeroed RAM or erased flash**. This core did not honour
   that: `control.v` cased on `op_code[6:2]` alone, so `32'd0` decoded as a LOAD and issued a phantom
   cache request. **That was a hardware hang, not a sim artifact** — Quartus zero-fills unwritten block
   RAM. Fixed 28 Aug by requiring `op_code[1:0] == 2'b11`, which every 32-bit RISC-V instruction has;
   anything else falls to `default` with all control bits low. Unit-tested across `0x00000000`,
   `0xFFFFFFFF`, two other bad `[1:0]` patterns, and a real LOAD.
3. **Then it becomes a trap** — [D3]'s `exception_detector`, `mcause = 2`.

The build flow is the standard one and needs no custom assembler: the **linker script** decides where
`.text`/`.data`/stack live, and `objcopy -O verilog` / `-O ihex` produces the memory image.
`.mif`/`.hex` init of block RAM at configuration time is the direct analogue of programming STM32
flash. Longer discussion, including the STM32/debugger mapping, in
[marathon § Fetching past the end](marathon.md#fetching-past-the-end-of-the-program-28-aug).

---

### The backing memory (28 Aug)

`data_mem.v` answers the cache's block port. The decision that shaped it: **the array is 32 bits wide
with a counter, not 512 bits wide, and not byte-addressed.**

- The address *space* is byte-addressed because RISC-V is; the array *width* is an implementation
  choice invisible above the cache. Those are separate questions and conflating them is what makes
  this look like a hard call.
- **Byte-wide buys nothing** — the cache already owns lane selection and write merge (23 Aug), so an
  8-bit array only makes the counter 64 deep instead of 8.
- **Block-wide costs the thing the model exists for.** A 256-bit row answers in one cycle, hiding
  exactly the stall bugs a backing model is meant to expose. The 8-beat counter gives realistic
  latency *as a consequence of the structure*, and `$readmemh` stays 1:1 with `objcopy` output.
- It is also the shape [E4]'s Avalon adapter needs, so that becomes a re-parameterisation rather than
  new thinking.

**MMIO does not constrain any of this.** `lsu.v` splits IO on `addr[31:28] == 4'hF` *before* routing,
so an IO access never reaches the cache or `data_mem` at all.

**The bug worth remembering: `mem_ready` is an accept signal, not a status flag.** `cache_controller`
drops `mem_addr_in_valid` (and `mem_data_out_valid`) the cycle it sees `mem_ready` — `l1.v:311`,
`l1.v:322`. A backing memory that advances its burst counter while `addr_in_valid` is high therefore
freezes on the second word and **hangs the core on the first cache miss**. The burst has to run off
latched state and an FSM, never off the input valids.

**Two things that look load-bearing and are not** — established by mutation testing, not by reading:

- Latching `addr_in` is *defensive*. `cache_controller` never clears `mem_addr_in`; it only overwrites
  it on the next request, so the address holds through the burst anyway.
- Masking the block base is *defensive*. `l1.v:735` already aligns:
  `miss_addr <= {addr_r[31:BLOCK_OFF_BITS], {BLOCK_OFF_BITS{1'b0}}}`, and likewise `evicted_address`.

Both are worth keeping — they make `data_mem` correct against any controller instead of depending on
undocumented hold-and-align behaviour in this one — but neither is what fixed the hang.

**Closed 28 Aug:** `data_mem` zeroes its array from an `initial` loop — same discipline as
`register_file`, which keeps a reset port off a 1024x32 array and matches what Quartus leaves unwritten
block RAM as. A real `.data` init path is still needed before the `sum.c` rung of the
[C ladder](#the-c-ladder), but the x-propagation hazard is gone.

---

### The datapath testbench (27 Aug)

`tb/cocotb/datapath/` — the whole-core, self-checking harness. This is what makes the `.S` suite in
[Day 1](#test-programs-tbcocotbdatapathasm) and the [C ladder](#the-c-ladder) mechanical to add:
write a `.s`, add a `Settings(...)`, done. **Extensive testing is now cheap; it wasn't before.**

```
 asm/x.s --as--> build/x.o --objcopy--> build/x.bin --> I_Mem_Model --> imem_data
     |                                                                      |
     +--> Golden_Model (Python ISA sim) --> (pc, regs) queues --> Scoreboard <-- Monitor <-- wb_*
```

Four pieces, matching the `register_file` structure:

- **`Golden_Model`** parses the same `.s` the assembler sees and executes it, queueing `(pc, regs[32])`
  per retired instruction. It runs to completion *before* the first clock edge, so the expected
  transaction count is known up front and `finish()` has a real target rather than a timeout.
- **`load_memories`** writes the image straight into `dut.IMEM.mem` and zeroes `dut.D_MEM.mem`.
  **Superseded the `I_Mem_Model` bus model on 28 Aug**, when both memories moved inside `data_path` and
  there was no longer a port to drive. `inst_mem`'s own `$readmemb` runs at time 0, before the test
  body, so it cannot load a per-test program — the TB writes the `.mem` file anyway to keep the
  synthesis path honest. Unused ROM locations are filled with **zero**, which `control.v` decodes as a
  reserved illegal encoding as of 28 Aug — so sim and hardware agree instead of the testbench papering
  over a hang (see [Fetching past the end](#fetching-past-the-end-of-the-program-28-aug)).
- **`Monitor`** samples at `wb_instr_valid`, records `wb_pc`, then waits for the falling edge (the
  register file's write edge) before snapshotting all 32 registers.
- **`Scoreboard`** compares both queues and prints a per-register diff on mismatch.

**`ebreak` terminates the program.** The golden stops when it decodes one; without it the golden just
runs off the end of the parsed list and the DUT keeps retiring NOPs. `r_type.s` has none and passes on
the length guard, but every test from here should end with `ebreak` so the two ends agree explicitly.

**Five things this cost to get right** — the last three are core-facing and will bite again:

- **A zero instruction word was not a safe filler.** `op_code[6:2]` of `32'd0` is `` `I_TYPE_3 `` — the
  *load* class — so fetching past the end of the program issued a cache request that the backing
  memory never answered, and the pipeline hung with no obvious cause. **Fixed properly in the RTL on
  28 Aug** rather than padded around: `control.v` now requires `op_code[1:0] == 2'b11`, so the
  spec-reserved all-zero word is inert. See
  [Fetching past the end](#fetching-past-the-end-of-the-program-28-aug).
- **Every model must be running before reset drops.** The PC is held at 0 through reset, so those reset
  cycles are exactly when the imem model has to be driving `program[0]`. Building it after
  `reset_dut()` meant the first post-reset edge latched a stale `imem_data` and **silently ate the
  instruction at pc 0** — every arithmetic result downstream was then wrong, with mismatches that
  pointed nowhere near the cause.
- **The golden's instruction index must equal the assembler's word index.** Comment lines, `.`
  directives and `label:`-on-the-same-line all break the 1:1 mapping and corrupt every branch offset.
  `load_asm` strips them. Related: an instruction the golden can't decode now **raises** rather than
  being skipped — skipping desyncs the queues by one and every later comparison is garbage.
- **cocotb 2.x: a 1-bit signal is a `Logic`, a vector is a `LogicArray`.** They share no accessor —
  `Logic` has neither `.to_unsigned()` nor `.integer`. `int()` is the one thing that works on both, is
  unsigned on both, and raises `ValueError` on x/z. Anything version-sniffing instead of type-sniffing
  is wrong.
- **`objcopy -O binary` output has no line structure.** It is a raw image — 4 little-endian bytes per
  instruction, no newlines. Size must be exactly 4 x instruction count. Adding a `.data` section or
  `.align` later will insert padding and break the 1:1 word mapping the golden assumes.

**Venv note:** a venv bakes its absolute path into every console script shebang, so moving the repo
breaks `cocotb-config` (and with it the whole `Makefile.sim` include) while `import cocotb` keeps
working — a confusing pair of symptoms. Repaired 27 Aug after the move under `amd_2027_plan/`; recreate
the venv or rewrite the shebangs if the repo moves again.

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

### Test programs (`tb/cocotb/datapath/asm/`)

> **Relocated and re-scoped 27 Aug.** These live in `tb/cocotb/datapath/asm/` and are checked by the
> [datapath testbench](#the-datapath-testbench-27-aug) against the golden model, per instruction —
> not by writing a known value to a known address and asserting once at the end. That was the plan when
> there was no golden model; per-instruction comparison localises a failure to the exact instruction
> instead of telling you only that the program ended wrong. End each one with `ebreak`.
>
> - ✅ `r_type.s` — R-type + immediate arithmetic, back-to-back dependencies. **Passing.**
> - 🚧 `b_type.s` — created, empty.

1. `arith.S` — every R-type op, checked against expected results
2. `imm.S` — every I-type op, **including `ADDI` with a negative immediate** (catches [B2](#b2--alu_controllerv)'s `funct_7` bug)
3. `shift.S` — `SLLI`/`SRLI`/`SRAI` and register-shift forms, shift amounts > 31 masked to 5 bits
4. `ldst.S` — all six load/store widths, aligned, including negative values through `LB`/`LH`
5. `branch.S` — all six branches, taken and not-taken, forward and backward
6. `jump.S` — `JAL`/`JALR`, verify link register and `JALR` LSB clearing
7. `lui_auipc.S` — `LUI` and `AUIPC` (**`AUIPC` will fail until you fix [B6](#b6--instruction_decoderv)**)

Once these pass, the `.S` suite stays the regression net — the [C ladder](#the-c-ladder) is stacked
on top of it, not instead of it. A C failure with a green `.S` suite means toolchain/crt0/linker; a C
failure with a red one means the core.

**Exit criteria (end of Saturday):** all 7 programs pass on the single-cycle core. This is the checkpoint that decides whether Tuesday is realistic — if you're not here by Saturday night, cut P2 (cache) immediately and protect P0.

---

## Day 2 — Sunday, the 5-stage pipeline (RV32I46F_5SP)

The riskiest day. Budget the whole day; do not add CSRs today no matter how well it's going.

- [x] ~~`★☆☆ P0` **Register file write-first behaviour**~~ — **done 23 Aug** ([B4](#b4--register_filev)). Write moved to `negedge clk`, so a WB write in cycle N is visible to an ID read in cycle N. Without it a distance-3 RAW reads stale, because forwarding only covers producers one and two instructions ahead.
  - **The `register_file` cocotb suite cannot catch this**, and that is now demonstrated rather than assumed: its driver applies stimulus on the falling edge, which is also the write edge, so it never exercises a same-cycle read-and-write the way a pipeline does. It still passes 100/100 either way. **`hazard.S` is what has to catch a regression here — make sure it includes a dependency at distance 3, not just 1 and 2.**
- [x] ~~`★★☆ P0` **Pipeline registers first, hazards second.**~~ — **done 24 Aug.** All four registers written, and `rtl/datapath.v` wires all five stages together. Elaborates clean under `iverilog -Wall`; a smoke test runs `addi/addi/add/add` and gets the right answers through both forwarding paths. Forwarding is already in, so the NOP-padded step was skipped. Verify with a test where every instruction is separated by 4 `NOP`s — all 7 Day-1 programs must pass in NOP-padded form. This isolates "did I wire the pipeline right" from "did I get hazards right", and that separation is what keeps Sunday from becoming an undebuggable mess.
- [x] ~~`★☆☆ P0` **⚠** **Wire in `rtl/forwarding_unit.v`**~~ — **done 24 Aug.** Instantiated in `datapath.v`, both paths exercised by the `addi/addi/add/add` smoke test. EX/MEM is tested before MEM/WB, which is the right priority for the double-hazard case. The forward sources are `em_src` and `wb_src` — the *writeback-source muxes*, not the raw ALU results — so a load's data forwards correctly without a separate path.
- [ ] `★☆☆ P0` **⚠** **Wire in `rtl/branch_logic.v`** — written 23 Aug, lints clean, 5/5 directed cases pass. Easy, but it needs `EX_pc`/`EX_imm` out of `ID/EX`, so the pipeline registers must exist first. See [Branch resolution in EX](#branch-resolution-in-ex) for what it needs from the pipeline registers.
- [ ] `★★☆ P0` **Static prediction.** Tie `branch_prediction = 0` (predict not-taken), resolve in EX, flush on `prediction_miss`. Get the pipeline *correct* before making it *fast* — the dynamic predictor is a Monday feature and can only change performance, never correctness. If it changes correctness, your flush logic is broken. With `branch_logic` already in place, switching to the real predictor on Monday is just changing what drives `branch_prediction`.
- [ ] `★★☆ P0` **⚠** Re-run all 7 test programs **unpadded**, then add `hazard.S`: back-to-back dependent ALU ops, load-immediately-followed-by-use, branch on a just-computed value, store of a just-loaded value, and a **distance-3 dependency** for the write-first path above. Last by dependency, not difficulty.
- [x] ~~`★★★ P0` `rtl/hazard_detector.v`~~ — **done 25 Aug.** Module `hazard_unit`, pure combinational, lints clean. Four jobs, all in:
  - **Load-use stall:** `ID/EX.MemRead && ID/EX.rd != 0 && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)` → stall PC + IF/ID, bubble ID/EX. Forwarding cannot fix this one; the data does not exist yet. **The `rd != 0` term also removes the need for `rs1_used`/`rs2_used` decoder outputs** — `instruction_decoder.v` leaves `rs1`/`rs2` at 0 for `JAL`/`LUI`/`AUIPC` and `rs2` at 0 for every I-type, so those can only match a producer whose `rd` is `x0`, which the term excludes. Non-local dependency, commented in both files.
  - **Control flush:** on a taken or mispredicted branch resolved in EX, flush `IF/ID` and `ID/EX`. `prediction_miss || ex_jump` — one arm, since with no predictor a taken branch and a jump need identical flushes.
  - **`mem_advance`** — the MEM/WB clock enable, exported back to the LSU so it can tell a new access from the same access still parked in MEM. Defined as `!req_stall`: a load-use stall lets MEM drain and must never appear in that term.
  - **Memory stall** — `req_stall` from the LSU, see below.

  **Priority: `req_stall` outranks every redirect.** With the flush arms first, a mispredict during a memory stall emits flushes and *no* stalls — EX/MEM advances and the in-flight load leaves MEM before its data returns. Letting the memory stall win is also self-healing: it freezes ID/EX, so `prediction_miss`/`ex_jump` are combinational off frozen contents and stay asserted until the stall lifts. The pending redirect cannot be lost, so nothing needs latching.

### The memory-stall handshake

**The memory stall needs an LSU, not just a hazard-unit input** — **built 25 Aug, `rtl/lsu.v`.** The
cache's CPU protocol is stateful and the hazard unit is combinational, so routing
`cpu_ready_out`/`cpu_data_out_valid` straight into it re-issues the request every stalled cycle:
duplicate loads, and duplicate **stores**. Four things the LSU had to get right, none of them obvious
from the cache's port list:

- **Issue once.** The FSM pulses the request and holds `req_stall` until the response.
- **Hold `valid` until accepted — do not pulse it.** The controller's real accept condition is
  `l1.v:166`, `cpu_data_in_valid & cpu_cache_ready`, and `cpu_cache_ready` is invisible from outside
  the module. After any miss the cache re-enters IDLE with `ready` still low (`l1.v:705` raises it a
  cycle later, and the refill's write-enables hold it low longer) while the controller has already
  re-asserted `cpu_ready_out`. A one-cycle pulse into that window is **silently dropped and the
  pipeline hangs forever**. `cpu_ready_out` falling is the only observable acknowledgement, so that is
  what the LSU uses.
- **`req_stall` must be combinational.** A registered stall reports the previous cycle, by which point
  the instruction it was protecting has already left MEM.
  - **⚠ Amended 29 Aug — that is true of *asserting*, and as originally written this bullet argued for
    the code that broke every load.** Deassertion has the opposite requirement: **the stall must not
    drop until the captured response is observable.** `cache_responded` is combinational, so
    `req_stall` fell in the same cycle the cache answered — but `be_cache_in <= resp_data` is
    non-blocking, so during that cycle it still held the *previous* value. MEM/WB latched at the end of
    it and every `lw` wrote back stale data. Fixed by bypassing the register on the response cycle
    (`be_cache_in = cache_responded ? resp_data : resp_data_r`), which costs no cycles; `resp_data_r`
    only has to hold the value for `DONE`. The general rule: **release the stall on the cycle the data
    is visible, not the cycle it is captured.**
- **A `DONE` state** for a response that arrives while something else is holding MEM — otherwise the
  access re-issues. Entered only when `mem_advance` is low on the response cycle.

Still open on the module: misaligned-access detection, which belongs in the issue path ahead of the
MMIO split.

**A memory stall is not a global freeze.** Hold `IF/ID`, `ID/EX`, `EX/MEM` — but **bubble `MEM/WB`**.
Holding MEM/WB instead makes WB re-commit the same instruction every cycle of the stall: idempotent for
a plain register write, so it tests fine, but it over-counts `minstret` and repeats CSR writes.

**Priority:** memory stall (deepest) beats load-use. And note flush and stall can be live at once on
different registers — a mispredict flushes IF/ID and ID/EX while a memory stall freezes EX/MEM. If you
build stall and flush as two global signals you will have to unpick that; keep them per-register.

### What belongs in a pipeline register

Settled 23 Aug while writing `ID_EX_reg` and `MEM_WB_reg`. Use this for `EX/MEM`, the last one.

**The rule:** carry every signal **produced at or before this stage** that is **read at or after the
next stage** — by *any* consumer, not just that stage's own datapath. The last clause is the one that
catches people out; it is why the paper's registers look over-stuffed.

Four categories, all of which have to be checked:

1. **Every input to a downstream mux.** `control.v:16` makes `mem_to_reg` a 5-way select
   (`000` ALU, `001` memory, `010` PC+4, `011` lui, `100` CSR), so all five values must reach WB.
   `PC+4`, the LUI immediate and `csrRD` are produced in ID and nothing recomputes them later — they
   ride three registers to get there. This is most of the apparent bloat, and it is unavoidable once
   the writeback source is chosen late.
2. **Control whose effect lands downstream** — `reg_write`, `mem_to_reg`, `csr_write`. Decoded once in
   ID, acted on in WB. Note the converse: `mem_read`/`mem_write` must *not* cross MEM/WB, because the
   access already happened. Signals stop travelling the moment their last reader is behind them.
3. **The destination** — `rd`. Easy to forget; without it the write has no target.
4. **Whatever the side units read out of this stage.** `forwarding_unit.v:8-13` reads
   `ID_EX_RS1`/`RS2` and `EX_MEM_RD`/`MEM_WB_RD` + their `RegWrite`s. The hazard unit reads the same
   pair. Traps need `WB.PC` for `mepc`, and `opcode`/`instr` for `mtval` and `minstret`. The debugger
   reads `WB.instr`. None of these are datapath, and all of them are in the paper's Fig. 2 registers.

**Gshare adds a fifth for this design:** the prediction payload
(`prediction_out`, `prediction_index`, `bhr_snap_index`, `prediction_valid`) must ride from IF to the
resolve point, or the update trains the wrong PHT entry and restores the wrong BHR snapshot
([B3](#b3--branch_predictorv)). The paper carries only `B.EST` because its predictor is a plain 2-bit
PHT with no history to recover.

**Flush and stall are not the same question at every stage:**

- `IF/ID`, `ID/EX` — flush is the mispredict/jump squash. Load-bearing from Day 2.
- `MEM/WB` — flush is **not** for mispredicts; an instruction here is already past the EX resolve
  point. It exists for the **trap squash**, so a faulting instruction cannot write back. Dead logic
  until Day 3, then essential.
- `stall` everywhere holds rather than bubbles, which is the global-freeze discipline `l1.v` needs on
  a cache miss.

### Datapath wiring (24 Aug)

`rtl/datapath.v` connects all five stages. Elaborates clean; smoke test executes
`addi x1,x0,5 / addi x2,x0,7 / add x3,x1,x2 / add x4,x1,x3` and produces 5, 7, 12, 17 — exercising
fetch, decode, control, `alu_controller`, ALU, both forwarding paths and writeback.

**Module ports.** `inst_mem.v` is still empty, so fetch is brought out as `imem_addr`/`imem_data`, and
the cache's backing-memory port is brought out too. Both get filled in when the mem units exist.

**One ordering bug worth remembering:** forwarding must be applied to the *register reads*, then the
`alu_src` mux selects. Doing it the other way round — source mux first, forward mux second — lets an
active forward overwrite the PC for `AUIPC`/`JAL`, or the CSR immediate. The same applies to store
data: `EX_MEM_reg.r_data_2` takes the **forwarded** `rd_2`, or `sw` of a just-computed value stores
stale data.

**Still tied off inside:**

- every stall is `1'b0`; flush on IF/ID and ID/EX is `ex_prediction_miss | ex_jump`
- `csr_read_data`, `trap`, `t_target` are zero; `csr_ready` is 1
- `cpu_data_in_valid` is driven straight off `em_mem_read | em_mem_write`, which re-issues the request
  every stalled cycle — the LSU has to take this over. `cpu_ready_out`/`cpu_data_out_valid` are
  brought out and waiting.
- the prediction is registered one cycle behind `btb_target`, which is combinational off `if_pc`.
  This skew needs resolving with the hazard unit.

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

**Exit criteria:** all Day-1 programs pass unpadded on the pipelined core, and its retired
architectural state matches the golden model instruction-for-instruction.

> **Status 27 Aug — partly met.** The comparison mechanism exists and works: the
> [datapath testbench](#the-datapath-testbench-27-aug) checks retired PC and all 32 registers against a
> golden ISA model on every instruction, which is a stronger check than the original "matches the
> single-cycle core at retirement" and does not require writing a single-cycle core at all. `r_type.s`
> passes, exercising fetch, decode, both forwarding paths and writeback. **What remains is coverage,
> not mechanism** — branches, jumps, loads/stores and the hazard cases still need programs written.
> Note the load/store tests will be the first to exercise the LSU and cache stall path through this
> harness, which needs a backing-memory model behind `l1.v` ([Day 4](#day-4--tuesday-cache-integration-p2));
> the TB currently ties `mem_ready` high and never answers, which is fine only while no program loads
> or stores.

---

## Day 3 — Monday, predictor + CSRs + traps

### Morning: the dynamic predictor

**This recommendation changed on 22 Aug.** The original plan was to write a throwaway 2-bit PHT and defer gshare to S3, because `rtl/branch_predictor.v` didn't compile and its recovery path looked unsound. Both concerns are gone — it compiles, lints to one benign warning, the index bug that would have stopped it learning is fixed, and the BHR recovery turned out to be correct ([B3](#b3--branch_predictorv)). **Use the gshare predictor. Don't write the simple one.**

What's left here is integration, not the predictor itself:

- [x] `★☆☆ P0` ~~Gate `history_read` on a fetch-word pre-decode~~ — **superseded 23 Aug by the BTB** ([D9](#d9-btb-structure-and-depth)). `history_read = hit_miss`: the BTB only holds PCs that resolved as branches in EX, so a hit *is* the "this is a branch" gate. Strictly better than pre-decoding the fetch word — it needs no instruction bits in IF, which matters once fetch goes through `l1.v` and the word isn't back yet.
  - **⚠ Polarity:** `hit_miss` is high on a **hit**. `history_read = hit_miss`, never `~hit_miss`.
- [x] `★☆☆ P1` ~~Extract the B-type immediate in IF for `B_Target`~~ — **superseded 23 Aug.** `btb.v` stores the resolved target from EX, so nothing recomputes `PC + imm` in IF. `if_imm_bits`/`branch_target` were removed from `branch_predictor.v` on 23 Aug.
- [x] `★☆☆ P1` ~~Carry `{prediction_out, prediction_index, bhr_snap_index, prediction_valid}` through `IF/ID` and `ID/EX`~~ — **done 23 Aug**, both registers. Dropped on flush in each. Note `branch_logic.v:11` wants a **1-bit** prediction: feed it `ex_branch_prediction[1]`, not the 2-bit bus.
- [ ] `★☆☆ P1` **Change the BTB target select to one-hot AND/OR** before growing the buffer, and raise `BUFFER_DEPTH` 4 → 8 ([D9](#d9-btb-structure-and-depth))
- [ ] `★★☆ P1` Wire `btb.v` into IF: `if_pc` from the PC, `target` → `pc_controller.branch_target`, `hit_miss` → `branch_predictor.history_read`, and the write port from EX branch resolution (`ex_pc`, `ex_target`, `ex_op_code`, `write_en`)
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
- [x] ~~`★★★ P2` **⚠ BLOCKER — sub-word access in the cache**~~ — **✅ resolved 23 Aug**, see
  [Sub-word access in the cache](#sub-word-access-in-the-cache-resolved). This was the item that made
  P2 expensive; with it gone, the cache is now the memory from the start
  ([Scope call](#scope-call-read-this-first)).
- [ ] `★☆☆ P2` **⚠** Re-run the **entire** test suite after wiring. A cache is a correctness-neutral optimisation: if any test changes result, the cache or the stall path is wrong, not the test. Trivial to run, last by dependency.
- [x] ~~`★★☆ P2` Build a backing-memory model with realistic latency~~ — **done 28 Aug as real RTL,
  not a model.** `rtl/data_mem.v` gets its latency from the 8-beat block burst rather than an injected
  delay. See [The backing memory](#the-backing-memory-28-aug)
- [x] ~~`★★☆ P2` Wire `cache_controller` in as the **data** memory only.~~ — **done 28 Aug.** The
  cache is the data path's memory, backed by `data_mem`; fetch stays on a plain ROM, which is exactly
  the "one variable at a time" ordering this item asked for.
- [ ] `★★☆ P2` Pipeline must stall on `!cpu_ready_out` and wait for `cpu_data_out_valid`. Your Day-1 interface decision makes this a hazard-unit change, not a datapath change.
- [ ] `★★★ P2` Only then consider the instruction side. Two independent stall sources into the same pipeline is materially harder than one.

- [ ] `★☆☆ P2` **⚠** Confirm the MMIO decoder sits *outside* `cache_controller`, so IO addresses never
  reach the cache. See [Memory-mapped IO](#memory-mapped-io) — cached MMIO is the failure that looks
  like a hung UART.

**Risk:** the cache's `BLOCK_BITS = 512` block against a 32-bit core means a miss moves 64 bytes. Make sure the miss path and the write-back FIFO drain logic are exercised — `tb/tb_ctrl.v` covers FIFO-full drain, which is the nastiest case, so that TB is worth trusting.

---

### Sub-word access in the cache (resolved)

`rtl/l1.v` was byte-only: `l1.v:848` read one byte and zero-extended it (an `LBU`), `l1.v:857` wrote
one byte (an `SB`), and there was no path that returned a full word. Fixed 23 Aug in ~26 lines.

**A `size` input was unavoidable** — byte-vs-word cannot be inferred from the offset bits alone. Added
as `cpu_size` on `cache_controller`'s CPU port (`00` byte, `01` half, `10`/`11` word), latched to
`size_r` inside `cache` alongside `byte_index_r`/`word_index_r`. Both strobes became a 3-way `case`
with **word as the `default`**, so an unrecognised encoding gives a full word rather than a partial
access.

**The split with the core.** The cache does *lane selection*; the core does *sign extension*. Sub-word
reads come back zero-extended and the core sign-extends `LB`/`LH` off `funct3[2]`. This differs from
the paper, which keeps its data memory dumb and puts shift + mask + extend all in one `BE_Logic` block
— fine for a plain RAM, but a cache has to own the write merge itself, because the modified word lands
in a cached block that gets written back later.

**One behaviour change:** the old byte-store took its data from `data_in_r[byte_index_r*8 +: 8]` — the
same lane the address selected. RISC-V `SB` puts the byte in `rs2[7:0]` regardless of address, so it is
now `data_in_r[7:0]` (and `[15:0]` for `SH`). `tb/tb_ctrl.v` does **not** cover this: every store in it
is at byte offset 0, where both expressions are identical.

**Testing.** `tb/tb_ctrl.v` needed `.cpu_size(2'b00)` added or every access takes the word path; with
it wired all its original checks pass unchanged. A separate test covers what it does not — word round
trip, byte reads at all four offsets, half reads at both, and `SB`/`SH`/`SW` merges. **That test is not
in `tb/` yet — move it there before trusting the sub-word path.**

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

- **`history_read` gating — ✅ settled 23 Aug: `history_read = hit_miss` from the BTB.** Supersedes the Fig. 2 pre-decode approach. The paper feeds the predictor `IF.opcode` because its instruction memory is combinational-read LUT RAM, so the fetch word is available in IF. Yours goes through `l1.v`, where it isn't — so the BTB answers "is this a branch, and where does it go" from the PC alone. See [D9](#d9-btb-structure-and-depth). The `instr` port added for pre-decode was removed 23 Aug.
  - **This is now a correctness requirement, not a preference.** [`branch_logic.v`](#branch-resolution-in-ex) reports `prediction_miss = 0` whenever `branch` is low. If an ungated predictor redirects the PC for a non-branch, that instruction reaches EX with `branch = 0`, nothing flushes, and execution continues from the wrong address with no recovery path.
- **~~The predictor does not compute `B_Target`~~ — ✅ resolved 23 Aug: the BTB owns targets.** `if_imm_bits`, `branch_target`, and the adder were removed from `branch_predictor.v`, which is now a pure PHT + BHR. `pc_controller.v`'s `branch_target` input is fed by `btb.v`'s `target` output. No IF-stage immediate extraction is needed.
- **Naming:** `predicted_valid` (input) vs `prediction_valid` (output) differ by one character and appear in the same expressions. Rename the input to `update_valid`.
- **Residual one-cycle skew** (won't fix): `current_index` uses `bhr` from the cycle before `prediction_valid` rises, while the snapshot uses `bhr` from the cycle after. Now that the index is carried separately this no longer affects PHT training — it only slightly degrades recovery fidelity.
- **Pipeline cost:** each in-flight branch carries 7 bits of `prediction_index`, 2 of `prediction_out`, `$clog2(BHR_SNAPS)` of snapshot index, and 1 valid bit. **`IF/ID` and `ID/EX` both done 23 Aug**, flush drops the payload in each so a squashed branch cannot train the PHT. The full chain predictor → IF/ID → ID/EX → update port elaborates with no width mismatches.

### B4 — `register_file.v`

**✅ All four resolved; write-first landed 23 Aug.** Verified by the cocotb suite at 100/100 plus a directed write-first test.

| | Issue | Resolution |
|---|---|---|
| 1 | `ADDR_WIDTH = 3` → 8 registers; RV32I has 32 | now `ADDR_WIDTH = 5` |
| 2 | `x0` was a normal writable register, so `addi x0,x0,0` (the canonical NOP) corrupted the zero constant | writes to addr 0 dropped, reads of addr 0 forced to zero |
| 3 | Registered read with no write-first bypass | read is combinational, and the write moved to `negedge clk` on 23 Aug so a WB write in cycle N is visible to an ID read in cycle N. Verified: `ID/EX` latches the new value at the end of that cycle |
| 4 | `$dumpfile`/`$dumpvars` inside the RTL | removed; waves now come from `WAVES ?= 1` in the cocotb Makefile, written to `sim_build/register_file.fst` |

Two changes made along the way that aren't in the original defect list:

- **`file <= 0` in the reset branch didn't elaborate** — you can't assign a scalar to an unpacked array in Verilog-2001, and iverilog doesn't support it in `-g2012` either. The array now has no reset at all and takes its power-up state from an `initial` loop, which is what `ramstyle = "logic"` wants: distributed RAM has no reset port, and forcing one would infer 1,024 flip-flops instead.
- **The `reset` port is gone**, since nothing used it any more.

**Watch this at synthesis (S1).** A `negedge` write makes the design dual-edge: the WB→RF write path now has half a clock period, 10 ns at 50 MHz. That should be comfortable, but it is a half-cycle path in static timing analysis and some flows flag dual-edge designs. If it ever bites, the alternative is a combinational bypass mux in the register file (`write_addr == read_addr && write_en → write_data`), which keeps everything posedge at the cost of a mux in the ID read path.

**Read style is settled: combinational read, `ID/EX` registers the operands.** This is the conventional structure and matches the paper's diagram. The consequence to hold onto is that the register file is now a plain memory, *not* a memory plus a pipeline stage — so `ID/EX` must latch `read_data_1/2`, and there is no hidden extra cycle in the operand path.

### B5 — `forwarding_unit.v`

**✅ Resolved 22 Aug, wired 24 Aug.** `ADDR_WIDTH = 5`, `parameter` keyword added, lints clean at `-Wall`. The undriven `source_a`/`source_b` outputs have been dropped — the datapath does that mux itself, and a module with undriven outputs is what makes a `-Wall` run stop being worth reading. The logic was always correct: EX/MEM is tested before MEM/WB, which is the right priority for the double-hazard case, and both paths suppress forwarding from `x0`.

**The `LW` → `SW` case needs no MEM→MEM forward.** An earlier note here asked for one. It isn't required, for two reasons that only became true once the rest of the pipeline landed:

- The load-use stall in `hazard_detector.v` already fires on it — `ex_mem_read && ex_rd == id_rs2` catches a store whose *data* comes from the load, not just one whose address does. The `SW` bubbles one cycle and the case is correct without any new path.
- After that bubble the load sits in MEM, and `forward_b = 2'b10` selects `em_src` — the writeback-source mux, which is `be_data_out` for a load, not the raw ALU result. So the loaded value forwards through the ordinary EX/MEM path.

A MEM→MEM forward would only remove that one bubble. It is a CPI optimisation, not a correctness fix, and belongs with the other measurement work rather than on the critical path.

**Store data is forwarded, not read raw.** `EX_MEM_reg.r_data_2` is fed `rd_2_fwd` (`datapath.v:458`), so `sw` of a just-computed value stores the new value. Reading `ex_rd_2` there instead is a silent wrong-data bug that only shows up in compiled code, where spill/reload pairs are everywhere.

Note the division of labour with [B4](#b4--register_filev) — this unit's `RD != 0` checks stop a stale *forward* of `x0`, but they never stopped a write to `x0` landing in the file. That required the register file's own hardwiring. Two separate guards; both are needed.

### B6 — `instruction_decoder.v`

| | Issue | Status |
|---|---|---|
| 1 | **`AUIPC` was missing** — `U_TYPE = 5'b01101` covered `LUI` only | ✅ **Fixed 22 Aug.** Split into `` `U_TYPE_1 `` (LUI) and `` `U_TYPE_2 `` (AUIPC, `5'b00101`), each with its own arm. Both use the same U-format immediate `{inst[31:12], 12'b0}`, so the two arms are identical and could merge |
| 2 | **The I-type arm never set `funct_7`**, so `SRAI` was indistinguishable from `SRLI` | ✅ **Fixed 22 Aug.** Shift immediates now take `funct_7 = inst_in[31:25]` and a 5-bit shamt. The guard is `inst_in[6:2] == `I_TYPE_4`, which matters: that case arm also covers LOAD and SYSTEM, whose funct_3 of 001/101 (`LH`, `LHU`, `CSRRW`, `CSRRWI`) would otherwise have their immediates truncated to 5 bits |
| 3 | `` `I_TYPE_1 `` (SYSTEM) needs the `csr`/`zimm` fields | ⚠ **Half done 25 Aug.** `r_imm` is now driven on every arm as the zero-extended immediate, so the SYSTEM arm carries `inst[31:20]` — which is the **CSR address**. `zimm` does *not* come from here: it is `inst[19:15]`, the rs1 field, and the datapath already sources it via `alu_src_1 = 2'b10` (`datapath.v:381`). Nothing reads `r_imm` yet — `wb_r_imm` is unused |

**Decide what `r_imm` actually is before Day 3 wires the CSR file to it.** Every arm is 32 bits wide and
correct, but only the SYSTEM one has a plausible consumer. A zero-extended `S`/`B`/`J` offset is not a
meaningful value for anything — zero-extending a signed offset only destroys the sign — so either cut
those arms and rename the port `csr_addr`, or keep them and write down who is supposed to read them.
Left as-is, it is four dead assignments that look load-bearing.

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

**✅ Settled 23 Aug — jumps are not predicted; accept the EX-resolution penalty.** `btb.v` only allocates
on `ex_op_code[6:2] == `` `B_TYPE ``, so `JAL`/`JALR` never get a BTB entry, never hit, and therefore never
gate `history_read` on. They always resolve in EX and cost the full ~2-cycle bubble. Same outcome as the
paper, reached through the BTB rather than a fetch-word pre-decode ([D9](#d9-btb-structure-and-depth)).

Revisit only once the full pipeline is working. A `JAL` target is computable in ID (it needs no
register), so redirecting there costs 1 bubble instead of 2 — but it adds a second redirect source and
another priority tier to [PC redirect priority](#pc-redirect-priority), which is not a thing to be
debugging alongside the hazard unit.

### D9. BTB structure and depth

**✅ Settled 23 Aug — 8 entries, and change the target select to one-hot AND/OR.**

The BTB replaces the paper's IF-stage pre-decode ([B3](#b3--branch_predictorv)). The paper can read
`IF.opcode`/`IF.imm` in fetch because its instruction memory is combinational-read distributed RAM.
Once fetch goes through `l1.v` the instruction word isn't back in time, so the target has to come from
a PC-indexed structure instead. `hit_miss` then does double duty: it *is* the "this PC is a branch"
gate that `history_read` needs.

**Measured cost** — yosys `synth_xilinx`, lookup path only, `ltp -noff`:

| entries | LUT levels (index-mux, as written) | LUT levels (one-hot AND/OR) | FFs |
|---|---|---|---|
| 4 | 10 | 8 | 254 |
| 8 | 13 | 10 | 507 |
| 16 | 17 | 11 | 1012 |
| 32 | 24 | 12 | 2021 |
| 64 | 37 | 13 | 4038 |

> ⚠ These are **Xilinx**-mapped via yosys; the board is Intel Cyclone/Quartus ([Scope call](#scope-call-read-this-first)).
> Absolute LUT/FF numbers will not transfer. The *scaling shape* will — it's a property of the netlist
> structure, not the target cell library.

**Two conclusions:**

1. **Depth is not the fmax problem; the priority encoder is.** As written, `buff_index_1` is built by a
   for-loop where each iteration overwrites the last, which synthesises to a serial mux chain — hence
   the near-linear growth (10 → 37). Replacing index-then-mux with a one-hot AND/OR reduction over the
   matching entries is associative, so synthesis rebalances it into a tree and depth goes logarithmic
   (8 → 13). **Do this before growing the buffer.**
2. **8 entries.** At the 25 MHz starting target ([S1](#stretch--after-tuesday)) there is ~40 ns of budget
   and the lookup is nowhere near binding at any of these sizes, so pick for hit rate, not timing.
   4 is likely too few for Dhrystone's inner loops; 8 covers them with round-robin replacement. With
   the one-hot fix, 8 → 16 costs about one extra LUT level, so growing later is cheap if the hit rate
   disappoints. Instrument mispredicts before deciding to grow.

**Storage note.** The array is `63 × N` flip-flops and cannot be RAM: a fully-associative lookup compares
every entry every cycle, so every bit must be visible to the comparators simultaneously. Resetting only
the valid bits does *not* change this — measured, no effect. If the buffer ever needs to be large
(64+), the structure has to change to direct-mapped or set-associative, where one PC-indexed entry is
read per cycle and the payload can live in RAM. Measured direct-mapped depth is flat at ~12–14 levels
regardless of size. Not worth it at N=8.

### D10. Where `alu_controller` lives

**✅ Settled 23 Aug — in ID, not EX.** `ID_EX_reg` carries a 4-bit `alu_op` rather than the 7-bit
`funct_7` the paper's ID/EX carries, because the paper decodes ALU control in EX and this design does
it in ID. Cheaper across the register, and one less thing in the EX path.

The cost is on the other side: ID now holds the register-file read, immediate generation, the control
unit *and* `alu_controller`, while EX is comparatively light. If ID turns out to be the critical path
at [S1](#stretch--after-tuesday), moving `alu_controller` back to EX is a contained change — carry
`funct_7` instead of `alu_op` and move the instance.

### D12. What gets forwarded

**Settled 24 Aug.** The forwarding unit emits selects only; the datapath holds the muxes. The paper
splits it the other way — its Hazard Unit does the rd/rs comparison and its Forward Unit contains the
muxes, which is why the paper's Forward Unit takes `MEM.imm(LUI)`, `MEM.ALUresult`, `MEM.csrRD`,
`MEM.D_RD`, `MEM.PC+4` and the same five again for WB. Those are just the five writeback sources.

Either split works. What is **not** optional: you must forward the value the producing instruction will
*write back*, not its ALU result. Forwarding `alu_result` blindly breaks `JAL` (link is PC+4), `LUI`
(value is the immediate), any CSR read, and — worst — a load at distance 2, which would forward the
address instead of the data.

`datapath.v` resolves this once per stage as `em_src` and `wb_src`, keyed off `mem_to_reg`, and
forwards those. That reuses the writeback mux instead of duplicating source selection inside the
forwarding unit.

**A forwarding source that gets bubbled must be captured, not re-derived — added 29 Aug.** This is the
second half of the rule above and it only bites once a memory access takes more than one cycle, so it
stayed hidden until `data_mem` landed.

A memory stall asserts `mem_wb_flush` (see [The memory-stall handshake](#the-memory-stall-handshake)),
deliberately, so WB does not re-commit. The consequence is that **a producer sitting in writeback is a
forwarding source for exactly one cycle**, while the consumer parked in EX re-derives its operand
combinationally on *every* cycle of the stall. The correct value is computed once and then thrown away:

```
addi x1, x0, 256     writes x1
sw   x24, 12(x1)     distance 1 -- forwards from EX/MEM, which is *stalled* (held), so it survives
lh   x2,  12(x1)     distance 2 -- needs MEM/WB, which is *flushed* after one cycle
```

The `lh` computed the right address on the first stall cycle, then fell back to the stale `ex_rd_1` it
read in ID for the remaining ~19, and EX/MEM latched the wrong one. It addressed `0x4098` instead of
`0x010c` — a silently wrong load, not a hang.

**Fix:** `ID_EX_reg` re-captures the forwarded operands while stalled —
`ex_rd_1 <= fwd_rd_1; ex_rd_2 <= fwd_rd_2;` — fed from the datapath's existing forwarding muxes. It is
a no-op when no forward is active, since the mux then selects `ex_rd_1` itself, so it captures exactly
on the cycle the value is available and holds it afterwards. No extra cycles, and the bubble semantics
that `mem_wb_flush` exists for are unchanged.

**Only `full_type.s` catches this.** Mutation-tested: with the capture disabled, `r_type`, `loop`,
`b_type` and `sl_type` all still pass. It needs a long cache stall *and* a distance-2 dependency across
it, which no shorter program in the suite combines.

**Not yet covered:** CSR read-after-write forwarding (the paper's `CSR_FWsrc`, `csr_hazard_wb`,
`csr_hazard_mem`). That compares CSR addresses, not register numbers — Day 3 work alongside Zicsr.

### D3. `x0` handling location
Hardwire in the register file (B4-2) rather than special-casing in the control path. One place, impossible to forget.

---

## Definition of done

- [ ] Every module lints clean under `verilator -Wall`
- [ ] All test programs pass on the 5-stage core, unpadded
- [x] Pipelined core's retired state is checked instruction-by-instruction against a golden ISA model
      (`tb/cocotb/datapath`) — **mechanism done 27 Aug, replaces the single-cycle-core oracle**
- [ ] Branch predictor demonstrably reduces mispredicts on a loop benchmark
- [ ] `ECALL` → handler → `MRET` round-trips correctly
- [ ] Cache integration leaves every test result unchanged
- [ ] **`fib_iter.c` and `fib_rec.c`, compiled by GCC, produce correct results in sim**
- [ ] Every program in the [C ladder](#the-c-ladder) passes
- [ ] `hello.c` prints over the MMIO UART model, and `SIM_EXIT` reports pass/fail to the TB
- [ ] MMIO verified uncached: a UART status poll terminates with the cache wired in
- [ ] `README.md` documents the deviations from the paper (D1, gshare-vs-2-bit, and the MMIO map)
- [ ] Clean commit history with a tag at `rv32i46f-5sp-verified`

---

## If you fall behind

Cut in this order — protect the working core above all:

1. **Cut P2 (cache).** It isn't in the paper. Nothing about paper-parity depends on it.
2. **Cut the dynamic predictor**, keep static predict-not-taken. Correctness is unaffected; you lose only CPI.
3. **Cut traps**, keep Zicsr. `RV32I43F` is still a legitimate milestone in the paper's own progression.
4. **Cut the pipeline.** `RV32I46F` single-cycle with CSRs and traps is a complete, working, honestly-describable RISC-V processor. A finished single-cycle core beats a half-debugged pipeline every time.
