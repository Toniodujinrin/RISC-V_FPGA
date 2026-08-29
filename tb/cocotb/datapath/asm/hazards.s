lui x1, 0
addi x1, x1, 512
auipc x2, 0
addi x3, x0, 10
loop_start:
add x4, x3, x1
sw x4, 0(x1)
lw x5, 0(x1)
sub x6, x5, x3
sll x7, x6, x3
srl x8, x7, x3
sra x9, x8, x3
sh x9, 4(x1)
lhu x10, 4(x1)
sb x10, 6(x1)
lb x11, 6(x1)
and x12, x11, x5
or x13, x12, x6
xor x14, x13, x7
slt x15, x14, x5
sltu x16, x15, x14
jal x17, subroutine
addi x3, x3, -1
bne x3, x0, loop_start
addi x18, x0, 100
addi x19, x0, -1
bltu x18, x19, forward_skip
addi x18, x0, 0
forward_skip:
bge x19, x18, bad_path
jal x0, terminate
bad_path:
addi x20, x0, 1
terminate:
lui x21, 2
srli x22, x21, 12
add x23, x22, x2
ebreak
subroutine:
addi x24, x16, 42
sw x24, 12(x1)
lw x25, 12(x1)
add x26, x25, x24
jalr x0, x17, 0
