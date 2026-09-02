"""GCC-compiled C on the core.

A C test is not checked against a golden model the way the .s suite is -- the
program checks itself and hands its verdict to SIM_EXIT, and this only reads the
exit code back. That is the whole reason SIM_EXIT was built first.

The loader helpers are imported from the datapath testbench rather than copied,
so there is one definition of how a program reaches the two memories.
"""
import os
import subprocess

import cocotb
from cocotb.clock import Clock
from cocotb.task import current_task
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from datapth_ctb import read_image, write_mem_file, load_memories, reset_dut, sig_int

HERE = os.path.dirname(os.path.abspath(__file__))
C_DIR = os.path.join(HERE, "c")
BUILD_DIR = os.path.join(HERE, "build")
CRT0 = os.path.join(HERE, "asm", "crt0.s")
LINK_SCRIPT = os.path.join(HERE, "link.ld")
#the toolchain ships no libc headers or implementations, so the freestanding
#ones in lib/ are compiled into every program (see lib/string.h)
LIB_DIR = os.path.join(HERE, "lib")
STRING_C = os.path.join(LIB_DIR, "string.c")


def compile_c(name):
    """
    compiles the c file, takes out .text binaries and .data binaries (since using havard arch and data and instr use different memories) 
    takes in the linker script and the ctr0.s script as inputs to compiler risc-v toolchain 
    """
    os.makedirs(BUILD_DIR, exist_ok=True)
    elf = os.path.join(BUILD_DIR, f"{name}.elf")
    text_bin = os.path.join(BUILD_DIR, f"{name}.text.bin")
    data_bin = os.path.join(BUILD_DIR, f"{name}.data.bin")

    subprocess.run([
        "riscv64-unknown-elf-gcc",
        "-march=rv32i", "-mabi=ilp32",
        #freestanding: no libc, no gcc startup files, main is just a function
        "-nostdlib", "-nostartfiles", "-ffreestanding",
        "-O2", "-Wall", "-Wextra",
        "-T", LINK_SCRIPT,
        "-I", LIB_DIR,
        CRT0, os.path.join(C_DIR, f"{name}.c"), STRING_C,
        "-o", elf,
        "-lgcc", #allows for complex arithmetic not supported by processor, and applies them in software
    ], check=True)

    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary",
                    "--only-section=.text", elf, text_bin], check=True)
    #.bss is NOLOAD so it contributes nothing here, which is correct: crt0 zeroes
    #it. objcopy zero fills the gaps between the sections it does emit
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary",
                    "--only-section=.rodata", "--only-section=.data",
                    elf, data_bin], check=True)
    return text_bin, data_bin

#tick_gen divides its CLOCK_SPEED parameter, not the testbench clock, so the
#baud on the pin is set by the divisor in *clocks* and has nothing to do with the
#nominal rate the index is named after. at the 1ns clock below, index 2 is
#325 clocks a tick, 16 ticks a bit -- 5200ns a bit, not the 104us 9600 baud would
#be. keep this in step with rtl/io/uart.v
UART_CLOCK_SPEED = 50_000_000
UART_TICK_RATES = (38400, 76800, 153600, 307200)
UART_TICKS_PER_BIT = 16


def uart_tick_ns(baud_idx, clk_period_ns):
    """the tick period in ns, which is the divisor tick_gen counts to"""
    return (UART_CLOCK_SPEED // UART_TICK_RATES[baud_idx]) * clk_period_ns


async def uart_probe(dut, char_list, baud_idx=2, data_bits=8, stop_bits=1,
                     clk_period_ns=1):
    """rebuild the bytes the transmitter shifts out of dut.uart_tx

    samples the way uart_rx does rather than once per bit: the falling edge is a
    candidate start bit, half a bit later is its centre, and every bit after
    that is one bit period on from that centre. sampling at whatever phase the
    edge happened to be caught at would sit on the bit boundaries instead.
    """
    tick_ns = uart_tick_ns(baud_idx, clk_period_ns)
    half_bit = (UART_TICKS_PER_BIT // 2) * tick_ns
    full_bit = UART_TICKS_PER_BIT * tick_ns

    while True:
        await FallingEdge(dut.uart_tx)
        #confirm at the centre -- a line that came back up is a glitch, not a frame
        await Timer(half_bit, "ns")
        if dut.uart_tx.value != 0:
            continue

        #lsb first on the wire
        byte_value = 0
        for i in range(data_bits):
            await Timer(full_bit, "ns")
            if dut.uart_tx.value == 1:
                byte_value |= 1 << i

        for _ in range(stop_bits):
            await Timer(full_bit, "ns")
            assert dut.uart_tx.value == 1, (
                f"framing error after {byte_value:#04x}: stop bit low")

        char_list.append(chr(byte_value))


async def run_c(dut, name, timeout_cycles=200000):
    """compile, load both memories, run until the program stores its exit code"""
    text_bin, data_bin = compile_c(name)
    words = read_image(text_bin)
    data_words = read_image(data_bin)
    cocotb.log.info(f"{name}: {len(words)} words of text, "
                    f"{len(data_words)} words of data")

    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    #padded to the full array: $readmemb warns on a short file, and a word left
    #over from the previous test would survive wherever this one does not reach
    write_mem_file(words + [0]*(len(dut.IMEM.mem) - len(words)),
                   os.path.join(BUILD_DIR, "test.mem"))
    write_mem_file(data_words + [0]*(len(dut.D_MEM.mem) - len(data_words)),
                   os.path.join(BUILD_DIR, "data.mem"))
    load_memories(dut, words, data_words)
    #.bss contributes nothing to the image, so RAM past the data would read as
    #zero whether or not crt0 cleared it -- which would make the clear loop
    #untestable. poison it, and only the clear can make a .bss global start at 0
    for i in range(len(data_words), len(dut.D_MEM.mem)):
        dut.D_MEM.mem[i].value = 0xDEADBEEF
    #nothing drives the pin, and an X reaches uart_rx's start bit detect
    dut.uart_rx.value = 1
    await reset_dut(dut)
    char_list = []
    cocotb.start_soon(uart_probe(dut,char_list))

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if sig_int(dut.exit_valid):
            return (sig_int(dut.exit_code),char_list)

    raise AssertionError(f"{name}: no SIM_EXIT store within {timeout_cycles} cycles")

@cocotb.test()
async def test_fib_iter(dut):
    """registers and branches only -- passes before .data or the stack work"""
    code,char_list = await run_c(dut, "fib_iter")
    assert code == 0, f"fib_iter returned {code}, expected 55"


@cocotb.test()
async def test_sum(dut):
    """.rodata reached RAM, and crt0 cleared .bss"""
    code,char_list = await run_c(dut, "sum")
    assert code == 0, f"sum returned {code}, expected 31"

@cocotb.test() 
async def test_fact_r(dut):
    code, char_list = await run_c(dut,"fact_rec")
    assert code == 0, f"fact_rec return {code}, expected 120"

@cocotb.test() 
async def test_divmod(dut):
    code,char_list = await run_c(dut,"fact_rec")
    assert code == 0, f"fact_rec return {code}, expected 19"

@cocotb.test()
async def test_uart(dut):
    """11 bytes at 5200ns a bit is 570us of frames, so this one needs the room"""
    code, char_list = await run_c(dut, "uart", timeout_cycles=1_000_000)
    assert code == 0, f"uart return {code}, expected 0"
    assert "".join(char_list) == "hello world", \
        f"uart transmitted {''.join(char_list)!r}"
