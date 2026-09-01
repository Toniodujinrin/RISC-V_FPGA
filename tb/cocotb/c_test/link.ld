/* Two regions, because the core is Harvard: instruction fetch reads IMEM and
 * nothing else, loads and stores reach RAM and nothing else. That is what makes
 * this script unusual -- .rodata cannot sit next to .text the way it normally
 * would, because the core has no data path to instruction memory and a load of
 * a string literal placed there would never return it. Everything a load can
 * touch lives in RAM, and there is no LMA/VMA split anywhere: the testbench
 * loads both images directly, so nothing needs copying at run time.
 *
 * IMEM is IMEM_DEPTH * 4 bytes, RAM is DATA_MEM_DEPTH * 4. Keep them in step
 * with rtl/datapath.v -- the linker is the only thing that will catch an
 * overflow, and only if the lengths here are honest.
 *
 * RAM's origin is arbitrary as far as the hardware goes: data_mem truncates an
 * address to its low bits, so RAM aliases every 4K. It is placed away from 0
 * only so that a data address never reads like a code address in a waveform.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
  RAM  (rw) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
  /* the pc resets to 0, so whatever lands first here is the reset vector.
   * crt0 puts _start in its own .crt section for exactly this reason: the
   * ordering then holds regardless of the order objects appear on the link line */
  .text : {
    *(.crt)
    *(.text .text.*)
  } > IMEM

  /* first RAM section, so the data image objcopy produces starts at ORIGIN(RAM)
   * -- the testbench loads it at word 0 of the array and assumes exactly that */
  .rodata : {
    . = ALIGN(4);
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > RAM

  .data : {
    . = ALIGN(4);
    *(.data .data.*)
    /* gp addressing reaches +-2K, so parking gp 0x800 into the small data area
     * covers 4K of globals in one instruction. crt0 loads this with relaxation
     * turned off, or the linker would rewrite that very load as gp-relative */
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
  } > RAM

  /* NOLOAD: .bss occupies addresses but contributes nothing to the image.
   * crt0 zeroes it between these two symbols -- they are defined here, which is
   * the only reason the assembly can refer to them */
  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __BSS_END__ = .;
  } > RAM

  _end = .;

  /* the stack grows down from the top of RAM towards .bss. nothing checks that
   * they do not meet -- 4K holds both for now, but a deep recursion is what
   * will break it first */
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);

  /DISCARD/ : { *(.comment) *(.note.*) *(.riscv.attributes) }
}
