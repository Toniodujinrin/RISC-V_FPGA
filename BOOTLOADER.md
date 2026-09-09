# UART Bootloader — build guide

Expands `marathon.md` [Track J](marathon.md#track-j--the-uart-hardware-bootloader-p1) into a
step-by-step build. Goal: replace the Quartus recompile loop (`compile_to_mem.py` → `.mif` →
re-fit, ~20 min) with a serial write and a button press (~2 s).

**Phase 1 loads `.text` *and* `.data` into on-chip M10K and has no SDRAM dependency.** That is a
change from `marathon.md` J6, which parked `.data` behind Track E. Adding a word write port to
`data_mem.v` costs the same twenty lines as the one on `inst_mem.v`, and it makes Phase 1 a
*complete* tool rather than half of one. Phase 2 moves `.data` to SDRAM when E8/E12 land.

---

## The decisions this encodes

| Question | Answer | Why |
|---|---|---|
| Arbiter or mux? | **Mux, qualified by `boot_active`** | The core is held in reset during the load, so there is nothing to arbitrate. See [Why not an arbiter](#why-not-an-arbiter). |
| Share `uart.v`'s APB port? | **No — own `uart_rx`/`uart_tx`** | ~70 flops against 40,553. Buys baud > 19200, and a load path the loaded program cannot break. |
| Why transmit at all? | **TX is a control channel, never part of the load path** | No program byte ever travels on it. See [Why TX at all](#why-tx-at-all). |
| ACK granularity? | **Per record. Never per word** | A per-word ACK costs a USB round trip every 4 bytes. See [Why not a per-word ACK](#why-not-a-per-word-ack). |
| Frame by length or by sentinel? | **Length prefix** | The payload is compiled machine code, so every sentinel value appears inside it. A `len` field makes the problem not exist. |
| What starts a load? | **`reset`** | The trigger is an input, the state is an output. See [Trigger vs. state](#trigger-vs-state). |
| Does the host wait for each ACK? | **No — stream, then read the replies** | Streaming and acknowledging are independent. See [Stream, do not stall](#stream-do-not-stall). |
| Board-initiated req byte? | **No** | A probe record buys the same liveness signal with no RTL. See [Stream, do not stall](#stream-do-not-stall). |
| Where does `.data` go? | **M10K in Phase 1, SDRAM in Phase 2** | Phase 1 then needs nothing from Track E. |
| Re-entry without a board reset? | **No** | Would need an always-on RX snoop that false-triggers on terminal input. Use KEY (`PIN_AJ4`). |
| Cache coherency on release? | **Reset caches with the core** | `marathon.md` J4's "simplest correct answer". Boot writes go *around* the cache, straight into the arrays. |

### Why not an arbiter

An arbiter resolves *concurrent* requests. A core in reset issues no fetches, no cache misses and
no MMIO, so exclusion here is by phase, not contention. A fixed-priority arbiter whose high-priority
master is asserted for the whole load is a mux with extra state and one extra failure mode:

- `SRAM_controller.v` has **no abort path**. A grant flipping during `READ_BURST`/`WRITE_BURST`
  desyncs `burst_counter`, the full-page burst never gets its `BST`, and the open row wedges it.
- `io_apb_bridge.v`'s ACCESS state has **no timeout** (your own note, `mmio.v:12`). Preempting a
  live APB transfer hangs the core permanently.

A mux switched only in a quiescent state cannot do either.

### Why TX at all

The data path really is rx → memory; TX carries no program bytes. It exists for the one reply byte
per record, and its value is entirely in failure visibility:

- **Retransmit on corruption.** Open-loop, a flipped bit becomes a program that jumps into the
  weeds, and you debug it as a CPU bug for an hour before suspecting the load. With NAK the loader
  resends the record and corruption never reaches the core.
- **Bring-up disambiguation.** This is the one that earns it. A first load can fail from a wrong
  divisor, a wrong pin, `rx_en` not tied to `boot_active`, or a desynced magic FSM — and all four
  look identical from the host, which is *nothing happens*. One reply byte splits that space, which
  is why Step 9 opens with a loopback.

Cost is ~40 flops plus the 2:1 pin mux, and the mux is a genuine new cost — without a bootloader TX
the mmio UART would drive `AK2` directly. It also brings one bug class with it, the GO ordering
hazard in Step 5. Both are worth paying to turn silent load failures into a byte you can read.

### Trigger vs. state

These are two different signals and collapsing them breaks the design.

The **trigger** — *enter boot mode* — is an input, and it already exists: it is `reset`. KEY is the
board reset, so pressing it arms the load. There is no separate request port.

The **state** — *we are loading right now* — must be an output, because only the bootloader knows
when the load is over. A button cannot hold it, for three reasons:

1. You would have to hold the button for the whole load — 1.8 s for 20 KB, 6 minutes for the K8
   WAD. Release mid-record and the core leaves reset with a half-written `.text`.
2. The exit is a protocol event, not a human one. Boot ends after the GO record's ACK has fully
   shifted out; a thumb cannot time a stop bit.
3. Driven from outside, nothing can ever *end* boot. `core_reset` ors in `boot_active` and the TX
   mux selects on it, so the GO record would arrive with nowhere to put its result and the core
   would stay in reset forever.

**Standalone operation** is the one case that wants a real input. Armed on every reset, a board with
no host attached sits waiting forever and never runs anything. If you want both modes, sample a
**slide switch** at reset instead of forcing the arm — a slide switch, not KEY, because it is
already stable when reset deasserts, so there is nothing to debounce and nothing to hold. Skip it
if the USB-serial is always plugged in; then serial *is* the boot path and the `.mif` stops
mattering.

### Why not a per-word ACK

Tempting, on the theory that a memory write needs backpressure. It does not. At 115200 a byte is
86.8 µs, so the four bytes of a word take 347 µs to arrive; storing them into M10K takes one cycle,
20 ns. Memory is ~17,000× faster than the wire and cannot fall behind.

Acknowledging anyway is expensive, because each ACK is a **round trip through USB-serial**, not just
wire time:

| | per word | 20 KB (5120 words) |
|---|---|---|
| wire time alone (4 B + 1 ACK) | 434 µs | 2.2 s |
| + 1 ms USB turnaround | ~1.4 ms | ~7 s |
| + default 16 ms FTDI latency timer | ~16 ms | **82 s** |

The bad case is worse than the Quartus recompile this exists to replace, and you do not control
which USB-serial bridge is soldered to the board. ACK per *record* instead, where one record can be
the whole `.text` section: 20 KB streamed continuously is ~1.8 s and one round trip.

Phase 2 does not change this. `SRAM_controller.v` drops `mem_ready` during a transaction, so there
is a genuine handshake — but a 32-byte block takes 2.8 ms to arrive against a burst write of a few
hundred ns. Hold the write until `mem_ready` and keep receiving; the wire stays the bottleneck by
four orders of magnitude and the stall never reaches protocol level.

### Stream, do not stall

The same argument keeps going one step further than it first appears, so take it there.

**Streaming and acknowledging are independent.** Because the board can never fall behind, the host
should send every record back to back at wire speed and read the accumulated reply bytes
afterwards — one byte per record, in order — rather than blocking on each. If a reply is a NAK, it
names its record by position; resend that one and re-read. The writes from the failed attempt
already happened, which is harmless because the resend overwrites them.

Blocking per record is what the round-trip table above punishes. It is nearly free at three records
(`.text`, `.data`, GO) but the `CHUNK = 256` split in Step 7 makes 80 of them, and 80 × 16 ms is
1.3 s of pure latency bolted onto a 1.8 s transfer. Pipelining removes it and costs nothing in RTL.

**The one record you must not pipeline is GO.** Read and check every data reply *before* sending it.
Pipelined blindly, GO drops `boot_active` and releases the core into a program you have not yet
confirmed loaded cleanly — and by then the NAK that would have told you is stuck behind the running
program's own UART output.

**A probe record replaces the heartbeat.** The one thing a board-initiated req byte buys is telling
*armed* from *dead* before you commit 20 KB. Open the loader with a single 4-byte record to `imem`
at 0 and wait for its ACK: same answer, one round trip, and it exercises the write path as well as
the link. It needs no timer in the bootloader, no second reply code, and no filtering rule on the
host — a heartbeat would put a stray byte in the reply stream that the loader has to skip. Word 0 of
imem is overwritten by the real `.text` moments later, so the probe costs nothing.

---

## Shape

```
                    ┌──────────────────────────────────────────┐
   uart_rx (W15) ───┼──┬──► bootloader.uart_rx   (rx_en = boot_active)
                    │  └──► mmio UART rx         (rx_en = 0 until sw enables)
                    │
   uart_tx (AK2) ◄──┼──── 2:1 mux on boot_active ─┬── bootloader tx
                    │                             └── mmio UART tx
                    │
   boot_active ─────┼──┬──► core_reset  |= boot_active
                    │  ├──► inst_mem write port enable
                    │  ├──► data_mem write port enable        (phase 1)
                    │  └──► 2:1 mux on SRAM_controller cpu port (phase 2)
                    └──────────────────────────────────────────┘
```

`rx` needs no mux — two receivers can sit on the same wire. `uart.v` gates its receiver with
`rx_en = uart_en && file[CONTROL_REG][2] && !overrun`, and `CONTROL_REG` resets to 0, so during
boot only the bootloader is listening. Tie the bootloader's `rx_en` to `boot_active` and after
release only the CPU's is.

`tx` is the one genuine conflict — one pin, two drivers — so it must be a mux.

---

# Phase 1 — `.text` + `.data` → M10K

No dependency on Track E. Buildable in an evening.

## Step 1 — Protocol

One record, repeated. Little-endian throughout.

```
off  size  field
  0     4  magic    'R' 'V' '3' '2'   (0x52 0x56 0x33 0x32)
  4     1  dest     0x00 imem | 0x01 dmem | 0x02 dram | 0xFF go
  5     4  addr     absolute byte address in the destination space
  9     4  len      payload byte count
 13   len  payload
13+len  4  sum      32-bit wrapping sum of the payload bytes
```

Reply, one byte per record: `0x06` ACK, `0x15` NAK (checksum), `0x21` NAK (bad header).

The **GO record** is `dest=0xFF, len=0`. The board ACKs it, then drops `boot_active`.

**The board never speaks first.** It is armed and listening from reset; the host opens the port and
streams. There is no request byte and no heartbeat — see [Stream, do not stall](#stream-do-not-stall)
for why the probe record replaces both.

**Records are self-contained.** `addr` is absolute — never an offset from a previous record — and
words auto-increment from it within the payload. No address state carries across records, which is
what lets a single NAK'd record be resent on its own instead of replaying everything before it, and
what lets records be sent out of order or with gaps. The host computes `addr` as
`ORIGIN + offset into the image`, but only the sum ever goes on the wire.

**`len == 0` is legal.** `S_LEN` must branch straight past `S_PAY` when the count is zero. GO needs
this already, and it is what lets the loader send an empty probe record.

Alignment rules — the loader enforces them, the hardware NAKs anyway as cheap insurance:

| dest | addr | len |
|---|---|---|
| `imem`, `dmem` | 4-byte aligned | multiple of 4 |
| `dram` | **32-byte aligned** | **multiple of 32** |

Use a wrapping sum, not CRC32 — it is a two-line adder in RTL and catches everything a serial link
realistically does to you. Add CRC later if you ever see a silent corruption.

**Resync:** any byte that fails to match at its magic position returns the FSM to `S_MAGIC[0]` and
re-tests *that same byte* against `'R'`. Without the re-test, a stream of `R R V 3 2` desyncs forever.

## Step 2 — Baud, and the ceiling you will hit

`tick_gen` in `rtl/io/uart.v` tops out at **19200** — its table is 2400/4800/9600/19200 only. At
19200 a 20 KB program takes ~11 s. That alone justifies the separate receiver: the bootloader gets
its own divisor without touching a verified module.

At 16× oversampling from 50 MHz, `div = 50e6 / (baud × 16)`:

| baud | div | actual | error | |
|---|---|---|---|---|
| 19200 | 162 | 19290 | +0.47% | `uart.v`'s max |
| **115200** | **27** | **115741** | **+0.47%** | **use this** |
| 230400 | 13.56 → 14 | 223214 | −3.1% | too far |
| 460800 | 6.78 → 7 | 446429 | −3.1% | too far |

**115200 is the practical ceiling from a 50 MHz clock at 16× oversampling.** `marathon.md` J5's
"raise it to 921600 later" is not reachable without a PLL or dropping to 8× oversampling — note it
there. 115200 is 11520 B/s: a 20 KB program is ~1.8 s, the K8 WAD is 6.1 min.

Expose the divisor as a parameter so simulation can collapse it:

```verilog
parameter CLOCK_SPEED = 50_000_000,
parameter BOOT_BAUD   = 115_200,
parameter BOOT_DIV    = CLOCK_SPEED / (BOOT_BAUD * 16)   // override to 1 in sim
```

**Timing headroom worth knowing:** one byte at 115200 is 10 bit-times = 4320 clocks. Every piece of
FSM work you do between bytes — word assembly, a memory write, even a full 32-byte SDRAM block
burst (~25 cycles) — is invisible against that. **You need no FIFO and no flow control.** That is
what keeps this design small; do not add either, and do not let the loader simulate one by blocking
on replies — see [Stream, do not stall](#stream-do-not-stall).

## Step 3 — `rtl/bootloader.v` front end

Reuse `uart_rx` and `uart_tx` from `rtl/io/uart.v` unchanged — both already take `tick` as an
input, so they need only a local tick generator.

```verilog
module bootloader
#(
  parameter DATA_WIDTH  = 32,
  parameter BLOCK_BITS  = 256,
  parameter CLOCK_SPEED = 50_000_000,
  parameter BOOT_BAUD   = 115_200,
  parameter BOOT_DIV    = CLOCK_SPEED / (BOOT_BAUD * 16)
)
(
  input  clk,
  input  reset,               // raw reset, NOT core_reset — or it resets itself

  input  rx,                  // straight off the pin
  output tx,                  // muxed onto the pin at top level

  output boot_active,

  // instruction memory word write port
  output reg [DATA_WIDTH-1:0] imem_waddr,
  output reg [DATA_WIDTH-1:0] imem_wdata,
  output reg                  imem_we,

  // data memory word write port
  output reg [DATA_WIDTH-1:0] dmem_waddr,
  output reg [DATA_WIDTH-1:0] dmem_wdata,
  output reg                  dmem_we,

  // sdram cpu-side port — phase 2, leave tied off until E12 lands
  output reg [DATA_WIDTH-1:0] dram_addr,
  output reg [BLOCK_BITS-1:0] dram_wdata,
  output reg                  dram_valid,
  output reg                  dram_write_read,
  input                       dram_ready
);
```

Tick generator — a plain counter, no table:

```verilog
reg [$clog2(BOOT_DIV+1)-1:0] tick_count;
reg tick;
always @(posedge clk, posedge reset)
  if (reset)                        begin tick <= 0; tick_count <= 0; end
  else if (tick_count == BOOT_DIV-1) begin tick <= 1; tick_count <= 0; end
  else                              begin tick <= 0; tick_count <= tick_count + 1'b1; end
```

Receiver and transmitter, fixed 8N1:

```verilog
uart_rx RX (
  .clk(clk), .reset(reset), .rx(rx), .tick(tick),
  .data_bits(3'd7),          // bit count minus one → 8 data bits
  .stop_bits(2'd1),
  .parity_en(1'b0), .parity_type(1'b0),
  .rx_en(boot_active),       // only listens while loading
  .data_out_valid(rx_valid), .data_out(rx_byte),
  .parity_err(), .busy()
);

uart_tx TX (
  .clk(clk), .reset(reset), .tick(tick),
  .tx_start(tx_start), .din(tx_byte),
  .data_bits(3'd7), .stop_bits(2'd1),
  .parity_en(1'b0), .parity_type(1'b0),
  .output_valid(tx_done), .busy(tx_busy), .tx(tx)
);
```

`tx_start` is a one-cycle pulse; `uart_tx` latches `din` with it.

`rx_en` is tied to `boot_active` and stays on for the whole load — do **not** gate it on TX state.
UART is full duplex on separate wires, and deafening the receiver while the transmitter is busy is
how you drop the first byte of a fast host's reply.

## Step 4 — Write ports on the memories

### `rtl/inst_mem.v`

It has **no write port at all** today. Add one in the existing clocked block — that is the standard
simple-dual-port template and infers an M10K cleanly:

```verilog
  input                  imem_we,
  input [DATA_WIDTH-1:0] imem_waddr,
  input [DATA_WIDTH-1:0] imem_wdata
  ...
  always@(posedge clk)
  begin
    if (imem_we) mem[imem_waddr[ADDR_WIDTH+1:2]] <= imem_wdata;
    imem_data    <= mem[trunc_addr];
    output_valid <= (imem_addr[DATA_WIDTH-1:2] < IMEM_DEPTH);
  end
```

Read-during-write to the same address returns old data. Irrelevant — the core is in reset, and
`datapath.v` forces `imem_araddr = reset ? 32'd0 : if_pc_next` anyway.

Also guard the init so a boot test can start from an empty array:

```verilog
  initial if (PROGRAM_FILE != "") $readmemb(PROGRAM_FILE, mem);
```

### `rtl/data_mem.v`

Same idea, but `mem[]` is already written from the FSM's `WRITING` state inside an async-reset
block, and during boot that block sits in its reset branch. Put the boot write in its **own always
block**:

```verilog
  always@(posedge clk)
    if (boot_we) mem[boot_waddr[ADDR_WIDTH+1:2]] <= boot_wdata;
```

Two write ports on one array infers a true dual-port M10K, which the C5 has. If the fitter ever
objects, the alternative is to drive `D_MEM`'s reset from the raw reset instead of `core_reset` and
mux the write source inside the existing block — more re-plumbing, same result.

**No `.bss` handling needed.** `crt0.s` zeroes it between `__bss_start` and `__BSS_END__`, and
`.bss` is `NOLOAD` in `link.ld`, so it never appears in the image.

### Address translation is free

`link.ld` puts RAM at `0x0001_0000` and both arrays truncate: `boot_waddr[ADDR_WIDTH+1:2]` with
`ADDR_WIDTH=10` gives `0x10000 >> 2 & 0x3FF = 0`. So **send the link address unmodified** — the
same truncation the LSU/cache path already uses lands it at word 0 of the array. Do not translate
in `load.py`.

## Step 5 — The FSM

```
  reset ──► S_MAGIC[0]

  S_MAGIC (idx 0..3) ─► S_DEST ─► S_ADDR (idx 0..3) ─► S_LEN (idx 0..3)
     ▲                                                      │
     │                                                      ▼
     └──── S_REPLY ◄── S_SUM (idx 0..3) ◄──────────────── S_PAY
                          │
                          └─(dest==0xFF)─► S_GO ─► boot_active = 0 on tx_done

  S_LEN ─(len == 0)─► S_SUM        // GO and the probe record take this edge
```

No arm state and no timer: the FSM is in `S_MAGIC[0]` from reset and the first byte off the wire
lands there like any other, so the resync rule below covers it for free.

Per-destination payload handling:

- **imem / dmem** — shift bytes into a 32-bit register, 2-bit byte counter. On the 4th byte assert
  `*_we` for one cycle with `*_waddr = addr + byte_count - 3`, then advance.
- **dram** (Phase 2) — shift into a 256-bit register, 5-bit byte counter. On the 32nd byte issue one
  block write and wait for the handshake.

Accumulate `sum` over every payload byte as you go; compare at `S_SUM`. On mismatch, reply `0x15`
and discard — the loader retransmits the record. The writes already happened, which is fine because
the retransmit overwrites them.

**The GO ordering gotcha:** `tx` is muxed on `boot_active`, so the ACK must be *fully transmitted*
before `boot_active` drops or the last byte gets truncated mid-frame. Wait for `tx_done`, not for
`tx_start`:

```verilog
S_GO: if (tx_done) boot_active_r <= 1'b0;
```

`boot_active` itself:

```verilog
reg boot_active_r;
always @(posedge clk, posedge reset)
  if (reset)                     boot_active_r <= 1'b1;   // armed out of reset
  else if (go && tx_done)        boot_active_r <= 1'b0;
assign boot_active = boot_active_r;
```

Armed by `reset`, cleared by the protocol — the two halves of [Trigger vs. state](#trigger-vs-state).
For standalone operation, sample the slide switch in the reset branch instead of forcing `1`.

Nothing else drives it. The board is listening from reset and stays silent until the host speaks.

## Step 6 — Top-level wiring (`rtl/RV32I.v`)

```verilog
  wire boot_active, boot_tx, core_tx;

  wire core_reset = rst_chain[1] | boot_active;
  assign uart_tx  = boot_active ? boot_tx : core_tx;

  bootloader BOOT (
    .clk(clk),
    .reset(rst_chain[1]),        // raw reset — not core_reset
    .rx(uart_rx), .tx(boot_tx),
    .boot_active(boot_active),
    ...
  );
```

`data_path`'s `uart_tx` output becomes `core_tx`. The write ports thread down through `data_path`
to `IMEM` and `D_MEM`.

**Reset release is safe as written.** `boot_active` clears on a clock edge, so `core_reset`
deasserts just after an edge — the same async-assert / sync-deassert discipline `rst_chain` already
uses, and it meets recovery for the same reason.

Add to `RV32I.qsf` (after line 89):

```tcl
set_global_assignment -name VERILOG_FILE rtl/bootloader.v
```

## Step 7 — `tools/load.py`

Reuse `compile_to_mem.py`'s `compile_c()` — it already emits exactly the two files you need,
`*.text.bin` (from `.text`) and `*.data.bin` (from `.rodata` + `.data`).

```python
IMEM_BASE = 0x0000_0000     # ORIGIN(IMEM) in link.ld
DMEM_BASE = 0x0001_0000     # ORIGIN(RAM)  in link.ld
CHUNK     = 256             # payload bytes per record

def record(dest, addr, payload):
    body = b'RV32' + bytes([dest]) + addr.to_bytes(4,'little') \
           + len(payload).to_bytes(4,'little') + payload
    return body + (sum(payload) & 0xFFFFFFFF).to_bytes(4,'little')
```

- Pad each image to a multiple of 4 (Phase 1) or 32 (Phase 2 `dram`) with zeros.
- Send `.text` at `IMEM_BASE`, `.data` at `DMEM_BASE`, then the GO record.
- **Probe first.** Send one 4-byte record to `imem` at 0 and wait for its ACK with a ~2 s timeout.
  No reply means the board is not armed, or the baud is wrong — stop there rather than streaming
  20 KB into a dead port. `.text` overwrites word 0 immediately after.
- **Then stream every data record back to back without blocking**, and read the replies afterwards —
  one byte per record, in order. See [Stream, do not stall](#stream-do-not-stall).
- Any NAK names its record by position: resend that record, re-read, retry up to 3 times, then abort
  with the offset.
- **Send GO only once every data reply has been read and checked.** Never pipeline it behind
  unverified records.
- One record per chunk, never per word — see [Why not a per-word ACK](#why-not-a-per-word-ack).
- Print a progress bar. Assert `len(text) <= IMEM_DEPTH*4` and `len(data) <= DATA_MEM_DEPTH*4` —
  4 KB of RAM is the first wall you will hit.

Open the port at 115200 8N1 with a ~2 s read timeout. A missing ACK means the FSM desynced; the
recovery is a KEY press, not a cleverer loader.

## Step 8 — Simulate before you fit

Two tests, in this order.

**8a — FSM alone.** New `tb/cocotb/boot/`, `TOPLEVEL = bootloader`, `-Pbootloader.BOOT_DIV=1`
(16 clocks/bit, 160 clocks/byte). Bit-bang a record onto `rx`, assert the `(waddr, wdata)` pairs
coming out of the write ports and the ACK byte on `tx`. Cover: good record, bad checksum → `0x15`,
bad magic → resync, GO → `boot_active` falls *after* the ACK's stop bit. Add two more: a `len == 0`
record replies without entering `S_PAY`, and two records sent back to back with no gap both land
and both reply, which is the streaming case Step 7 depends on.

**8b — Full top.** `TOPLEVEL = RV32I`, `-PRV32I.PROGRAM_FILE=""` so imem starts empty. Feed a real
compiled program, send GO, then check it runs. `RV32I.v` leaves `exit_valid`/`exit_code`
unconnected, so probe them hierarchically as `dut.core.exit_valid` — Icarus allows it. Use a small
assembly test from `tb/cocotb/datapath/build/`, not a C program: at 160 clocks/byte a 4 KB image is
650 k cycles.

Copy the source list from `tb/cocotb/c_test/Makefile` and add `rtl/RV32I.v` and `rtl/bootloader.v`.

## Step 9 — Board bring-up

Order matters — each step isolates one failure.

1. **Fit and program.** Watch `io_slv_err` (`PIN_AA24`); it should stay dark.
2. **Loopback first.** Before trusting the FSM, confirm the pins and baud: send a byte, scope or
   check `tx`. Wrong baud looks exactly like a broken FSM.
3. **Send one probe record**, 4 bytes to `imem` at 0. Expect `0x06`. This is the first end-to-end
   proof — arm, baud, both pins, FSM and write port. No ACK ⇒ baud or resync, not memory.
4. **Send two records back to back** without reading between them, then read both replies. This is
   the streaming path Step 7 uses, and it is the one thing the single-record test does not cover.
5. **Send GO with nothing loaded.** The core runs zeros — `0x00000000` is an illegal instruction and
   the core has no trap path yet, so expect a hang, not a crash. This confirms release works.
6. **Load a real program and GO.** `programs/uart.c` exercises the whole stack.
7. **Press KEY, reload a different program.** That is the loop you built this for.

---

# Phase 2 — `.data` → SDRAM

**Gated on Track E.** `grep` finds `SRAM_controller` only in its own file — it is not instantiated
anywhere, and `data_mem.v` is still `l1.v`'s backing store. The two handshakes differ:
`data_mem` accepts on `addr_in_valid && (!write_read || data_in_valid)`, the controller accepts on
`cpu_in_valid && mem_ready` in `NORMAL_IDLE`. E8/E12 must land first.

When they do, the change is small:

**The mux.** On `SRAM_controller`'s cpu port, `l1.v` versus the bootloader, selected by
`boot_active`. **Switch only in `NORMAL_IDLE && mem_ready`** — see [Why not an arbiter](#why-not-an-arbiter).
The core is in reset so `l1.v` is quiet, but assert the condition anyway; it costs one AND gate and
it is the failure that takes an evening to find.

**Wait for init.** `Pwait = (100000+19)/20 = 5000` cycles at `T_CLK=20` — 100 µs before `mem_ready`
first rises. Gate the first block on `mem_ready`, not on a timer.

> `marathon.md:838` calls `reset_mem` "currently an unused port" to hang this on. There is no such
> port — the controller has only `reset`. Stale line; fix it there.

**Block granularity is a gift.** `cpu_addr_in[23:11]` = row, `[25:24]` = bank, `[10:5]` = column
high, so `addr[4:0]` is the offset inside a 32-byte block (16 × 16-bit, `BURST_LEN=16`). The
bootloader buffers 32 bytes and issues whole aligned blocks, which means **no read-modify-write
anywhere in the loader**. The cost is that `load.py` must zero-fill the trailing partial block.

**Destination field, not just an address.** Already in the protocol above — Harvard means byte 0 is
a legal address in both spaces, so `dest` is what disambiguates. Phase 1 built this in; nothing
changes but adding the `0x02` case.

**Refresh needs no thought.** `REFRESH_PERIOD = 64e6/(8192×20) = 390` cycles, and the controller
issues its own refresh from `NORMAL_IDLE`. One block write per 32 bytes = one per 138,240 clocks at
115200 baud. There is no bandwidth question here.

---

## Failure reference

| Symptom | Look at |
|---|---|
| No ACK, ever | Baud (Step 2 table), or `rx_en` not tied to `boot_active` |
| Probe ACKs, streaming drops records | RX overrun — the FSM is not consuming `rx_valid` in the byte time (Step 2 headroom) |
| Fewer replies than records sent | Same as above, or the loader read before all replies arrived — size the read by record count, not by timeout |
| Load crawls, seconds per KB | Loader is blocking on each ACK, or ACKing per word ([why](#why-not-a-per-word-ack)) |
| Runs a corrupt program, no NAK seen | GO pipelined behind unchecked replies ([why](#stream-do-not-stall)) |
| First record ACKs, later ones NAK `0x21` | Magic resync missing the re-test of the failing byte |
| Last ACK byte arrives truncated | `boot_active` dropped on `tx_start` instead of `tx_done` |
| Loads fine, runs the *previous* program | I-cache not invalidated / caches not reset with the core (J4) |
| Runs garbage after a good load | `.data` written to imem or vice versa — check the `dest` field |
| Core hangs immediately after GO | Expected with an empty imem (illegal instruction, no trap path) |
| SDRAM writes corrupt after the first block | Port mux switched outside `NORMAL_IDLE` |
| First SDRAM block lost | First write issued before `mem_ready` (100 µs init) |

## Checklist

- [ ] **J1** Protocol frozen (Step 1), including `len == 0`
- [ ] **J2a** `bootloader.v` front end + tick gen (Steps 2–3)
- [ ] **J2b** Write port on `inst_mem.v` (Step 4)
- [ ] **J2c** Write port on `data_mem.v` (Step 4) — *new, makes Phase 1 complete*
- [ ] **J2d** FSM (Step 5)
- [ ] **J2e** Top-level wiring + qsf (Step 6)
- [ ] **J3** `tools/load.py` (Step 7)
- [ ] **J-test** cocotb FSM test + full-top test (Step 8)
- [ ] **J4** Board bring-up (Step 9)
- [ ] **J5** Note the 115200 ceiling in `marathon.md`
- [ ] **J6** SDRAM port mux — *blocked on E8/E12* (Phase 2)

**If you are short on time,** cut Phase 2, the CRC, and the `dmem` write port — `.text`-only over
UART with `.data` still coming from a `.mif` is already most of the win, because `.text` is what
changes on every edit.
