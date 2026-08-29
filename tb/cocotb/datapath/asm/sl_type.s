addi x1, x0, 100
addi x2, x0, 200
addi x3, x0, 400
addi x4, x0, -1
addi x5, x0, 255
addi x6, x0, -256
addi x7, x0, 0
addi x8, x0, 1020
addi x9, x0, 512
sw x4, 0(x7)
lw x10, 0(x7)
sh x5, 4(x7)
lh x11, 4(x7)
lhu x12, 4(x7)
sb x6, 6(x7)
lb x13, 6(x7)
lbu x14, 6(x7)
sw x1, 12(x7)
lw x15, 12(x7)
sh x2, 16(x7)
lh x16, 16(x7)
sb x3, 18(x7)
lb x17, 18(x7)
lbu x18, 18(x7)
sw x4, 0(x8)
lw x19, 0(x8)
sh x5, -4(x8)
lh x20, -4(x8)
lhu x21, -4(x8)
sb x6, -6(x8)
lb x22, -6(x8)
lbu x23, -6(x8)
sw x4, 0(x9)
lw x24, 0(x9)
sh x4, 4(x9)
lh x25, 4(x9)
lhu x26, 4(x9)
sb x4, 6(x9)
lb x27, 6(x9)
lbu x28, 6(x9)
sw x6, -4(x9)
lw x29, -4(x9)
sh x6, -8(x9)
lh x30, -8(x9)
lhu x31, -8(x9)
sw x5, 252(x9)
lw x1, 252(x9)
sh x5, 256(x9)
lh x2, 256(x9)
lhu x3, 256(x9)
sb x5, 258(x9)
lb x4, 258(x9)
lbu x5, 258(x9)
sw x2, -252(x9)
lw x6, -252(x9)
sh x2, -256(x9)
lh x7, -256(x9)
lhu x8, -256(x9)
sb x2, -258(x9)
lb x11, -258(x9)   # was lb x9: clobbering the base makes the next address
                   # wrap into the 0xF mmio page, which has no slave yet
lbu x10, -258(x9)
ebreak
