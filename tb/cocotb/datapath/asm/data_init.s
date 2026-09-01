# proves .data reaches the core: the testbench preloads word 0 of RAM with
# 0xDEADBEEF, and this loads it back through the cache and hands the difference
# to SIM_EXIT. a non zero exit code means the preloaded image never arrived
li   x1, 0xDEADBEEF
addi x2, x0, 0
lw   x3, 0(x2)
sub  x4, x3, x1
lui  x6, 0xF0000
sw   x4, 252(x6)
loop:
  jal x0, loop
