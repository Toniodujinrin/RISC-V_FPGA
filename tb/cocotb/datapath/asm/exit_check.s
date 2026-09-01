# proves the SIM_EXIT path: computes 5 + 7 - 12, which is 0 only if the core is
# right, and stores it as the exit code. this is the shape every C test takes --
# the program decides its own pass/fail and the testbench only reads the code
addi x1, x0, 5
addi x2, x0, 7
add  x3, x1, x2
addi x4, x0, 12
sub  x5, x3, x4
lui  x6, 0xF0000
sw   x5, 252(x6)
loop:
  jal x0, loop
