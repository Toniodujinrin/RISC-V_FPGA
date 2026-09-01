.section .crt 
.global _start 
.type _start,@function 

_start:
#Initialize global pointer 
.option push
.option norelax 
  la gp,(__global_pointer$) 
.option pop 
  #stack grows down from the top of ram. nothing sets sp for us and the reset
  #value is 0, so without this the first prologue pushes to 0xFFFFFFF0, which
  #the lsu decodes as mmio -- every spill would silently vanish into the bridge
  la sp, __stack_top 
  #clear bss segment 
  la a0, __bss_start 
  la a1, __BSS_END__ 
  li a2,0

clear_bss: 
  bgeu a0, a1, done_bss 
  sb a2, 0(a0)
  addi a0, a0, 1
  beq x0,x0,clear_bss 

done_bss: 
  call main 
  #main's return value is the exit code, 0 being a pass. the store ends the run
  li t0, 0xF0000000 
  sw a0, 252(t0) 

hang: 
  #sim_exit has already stopped the run, this only catches the case where it did
  #not answer -- without it execution would run off the end of the program
  beq x0,x0,hang 
  .size _start, .-_start
