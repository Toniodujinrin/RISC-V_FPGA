#!/usr/bin/env python3
"""Compile one C file for the core and write the imem/dmem init images next to it.

Extracted from tb/cocotb/c_test/c_ctb.py's compile_c + write_mem_file path:
the same gcc/objcopy commands against crt0.s and link.ld, the same $readmemb
output format. It prompts for the C file path and writes test.mem and data.mem
into that file's own directory.

    python compile_to_mem.py
    path to the C file: tests/c/fib_iter.c
"""

import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
C_TEST_DIR = os.path.join(HERE, "tb", "cocotb", "c_test")
CRT0 = os.path.join(C_TEST_DIR, "asm", "crt0.s")
LINK_SCRIPT = os.path.join(C_TEST_DIR, "link.ld")
#the toolchain ships no libc headers or implementations, so the freestanding
#ones in lib/ are compiled into every program (see lib/string.h)
LIB_DIR = os.path.join(C_TEST_DIR, "lib")
STRING_C = os.path.join(LIB_DIR, "string.c")

# must match IMEM_DEPTH / DATA_MEM_DEPTH in rtl/datapath.v: the images are
# padded to the full array, or words left over from a previous build would
# survive wherever this one does not reach
IMEM_DEPTH = 8192
DATA_MEM_DEPTH = 1024


def read_image(file_name):
    """raw little endian image, i.e. what objcopy -O binary produces"""
    with open(file_name, "rb") as file:
        image = file.read()
    assert len(image) % 4 == 0, f"{file_name} is not a whole number of words"
    return [int.from_bytes(image[i:i+4], "little") for i in range(0, len(image), 4)]


def write_mem_file(words, path):
    """$readmemb format: one word of binary digits per line, which is what
       inst_mem.v and data_mem.v read at time 0"""
    with open(path, "w") as file:
        for word in words:
            file.write(f"{word:032b}\n")


def compile_c(c_file):
    c_dir = os.path.dirname(c_file)
    name = os.path.splitext(os.path.basename(c_file))[0]
    elf = os.path.join(c_dir, f"{name}.elf")
    text_bin = os.path.join(c_dir, f"{name}.text.bin")
    data_bin = os.path.join(c_dir, f"{name}.data.bin")

    subprocess.run([
        "riscv64-unknown-elf-gcc",
        "-march=rv32i", "-mabi=ilp32",
        #freestanding: no libc, no gcc startup files, main is just a function
        "-nostdlib", "-nostartfiles", "-ffreestanding",
        "-O2", "-Wall", "-Wextra",
        "-T", LINK_SCRIPT,
        "-I", LIB_DIR,
        CRT0, c_file, STRING_C,
        "-o", elf,
        "-lgcc", #software mul/div/etc, the core has no M extension
    ], check=True)

    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary",
                    "--only-section=.text", elf, text_bin], check=True)
    #.bss is NOLOAD so it contributes nothing here, which is correct: crt0
    #zeroes it. objcopy zero fills the gaps between the sections it does emit
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary",
                    "--only-section=.rodata", "--only-section=.data",
                    elf, data_bin], check=True)
    return text_bin, data_bin


def main():
    rel_path = input("path to the C file: ").strip()
    c_file = os.path.abspath(rel_path)
    if not os.path.isfile(c_file):
        print(f"no such file: {c_file}")
        return 1

    text_bin, data_bin = compile_c(c_file)
    words = read_image(text_bin)
    data_words = read_image(data_bin)
    assert len(words) <= IMEM_DEPTH, \
        f"program is {len(words)} words, imem holds {IMEM_DEPTH}"
    assert len(data_words) <= DATA_MEM_DEPTH, \
        f"data image is {len(data_words)} words, ram holds {DATA_MEM_DEPTH}"

    c_dir = os.path.dirname(c_file)
    write_mem_file(words + [0]*(IMEM_DEPTH - len(words)),
                   os.path.join(c_dir, "test.mem"))
    write_mem_file(data_words + [0]*(DATA_MEM_DEPTH - len(data_words)),
                   os.path.join(c_dir, "data.mem"))

    print(f"{os.path.basename(c_file)}: {len(words)} words of text, "
          f"{len(data_words)} words of data")
    print(f"wrote {os.path.join(c_dir, 'test.mem')} "
          f"({IMEM_DEPTH} words) and {os.path.join(c_dir, 'data.mem')} "
          f"({DATA_MEM_DEPTH} words)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
