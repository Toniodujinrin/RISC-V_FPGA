lui x1, 4096
auipc x2, 0
addi x3, x0, 512
addi x4, x0, 1020
addi x5, x0, -1
add x6, x1, x5
sub x7, x1, x6
sll x8, x7, x3
slt x9, x5, x7
sltu x10, x5, x7
xor x11, x9, x10
srl x12, x1, x7
sra x13, x5, x7
or x14, x11, x12
and x15, x13, x14
slti x16, x15, 0
sltiu x17, x15, 10
xori x18, x17, 255
ori x19, x18, 128
andi x20, x19, 63
slli x21, x20, 4
srli x22, x21, 2
srai x23, x22, 1
sw x23, 0(x3)
sh x22, 4(x3)
sb x21, 6(x3)
lw x24, 0(x3)
lh x25, 4(x3)
lhu x26, 4(x3)
lb x27, 6(x3)
lbu x28, 6(x3)
sw x24, -4(x4)
lw x29, -4(x4)
jal x30, test_branches
lui x31, 2
auipc x1, 4
jal x0, end_program
test_branches:
beq x24, x29, b1_pass
addi x2, x0, 1
b1_pass:
bne x24, x0, b2_pass
addi x2, x0, 2
b2_pass:
blt x5, x0, b3_pass
addi x2, x0, 3
b3_pass:
bge x0, x5, b4_pass
addi x2, x0, 4
b4_pass:
bltu x0, x5, b5_pass
addi x2, x0, 5
b5_pass:
bgeu x5, x0, b6_pass
addi x2, x0, 6
b6_pass:
add x3, x30, x0
jalr x0, x3, 0
end_program:
addi x1, x0, 256
sw x24, 12(x1)
lh x2, 12(x1)
sh x2, 16(x1)
lbu x3, 16(x1)
sb x3, 18(x1)
ebreak
