addi x1, x0, 15
addi x2, x0, 30
addi x3, x0, -10
addi x4, x0, -10
jal x5, branch_tests
addi x6, x0, 100
jal x0, loop_test
branch_tests:
beq x1, x2, fail_path
beq x3, x4, pass_beq
fail_path:
addi x7, x0, 1
pass_beq:
bne x1, x2, pass_bne
bne x3, x4, fail_path2
fail_path2:
addi x8, x0, 1
pass_bne:
blt x3, x1, pass_blt
blt x2, x1, fail_path3
fail_path3:
addi x9, x0, 1
pass_blt:
bge x2, x1, pass_bge
bge x3, x1, fail_path4
fail_path4:
addi x10, x0, 1
pass_bge:
bltu x1, x2, pass_bltu
bltu x3, x1, fail_path5
fail_path5:
addi x11, x0, 1
pass_bltu:
bgeu x3, x1, pass_bgeu
bgeu x1, x2, fail_path6
fail_path6:
addi x12, x0, 1
pass_bgeu:
add x13, x5, x0
jalr x0, x13, 0
loop_test:
addi x14, x0, 5
loop_start:
addi x14, x14, -1
bne x14, x0, loop_start
addi x15, x0, 10
jal x16, skip_ahead
addi x15, x15, 99
skip_ahead:
beq x15, x0, halt
addi x15, x15, -2
bge x15, x0, skip_ahead
halt:
ebreak
