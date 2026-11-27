# prog_arith.asm — arithmetic, logic, shifts, compare, and every
# load/store size. Expected final state (checked by tb/cpu_arith_tb.v):
#   x3=35  x4=15  x5=3   x6=47  x7=44  x8=40  x9=12  x10=-4
#   x11=1  x12=0  x13=35 x14=15 x15=35 x16=10 x17=35 x18=-1
#   x19=-1 x20=255 x21=-1 x22=65535
#   mem[0]=35  mem[4]=15  mem[8]=0x00000A23  mem[12]=35
#   mem[16]=0  mem[20]=0xFFFFFFFF

    addi x1, x0, 10        # x1 = 10
    addi x2, x0, 25        # x2 = 25
    add  x3, x1, x2        # 35
    sub  x4, x2, x1        # 15
    and  x5, x3, x4        # 35 & 15 = 3
    or   x6, x3, x4        # 35 | 15 = 47
    xor  x7, x3, x4        # 35 ^ 15 = 44
    slli x8, x1, 2         # 10 << 2 = 40
    srli x9, x2, 1         # 25 >> 1 = 12
    addi x10, x0, -8       # x10 = -8
    srai x10, x10, 1       # -8 >> 1 (arith) = -4
    slt  x11, x1, x2       # 10 < 25 signed -> 1
    sltu x12, x2, x1       # 25 < 10 unsigned -> 0

    sw   x3, 0(x0)         # mem[0] = 35
    sw   x4, 4(x0)         # mem[4] = 15
    lw   x13, 0(x0)        # 35
    lw   x14, 4(x0)        # 15
    sb   x3, 8(x0)         # mem[8] byte 0 = 0x23
    lb   x15, 8(x0)        # 0x23 = 35 (sign-extended)
    sb   x1, 9(x0)         # mem[8] byte 1 = 10 (neighbour untouched)
    lbu  x16, 9(x0)        # 10 (zero-extended)
    sh   x3, 12(x0)        # mem[12] low half = 35
    lh   x17, 12(x0)       # 35 (sign-extended)
    sw   x0, 16(x0)        # mem[16] = 0
    addi x18, x0, -1       # x18 = 0xFFFFFFFF
    sw   x18, 20(x0)       # mem[20] = 0xFFFFFFFF
    lb   x19, 20(x0)       # sign-extended byte 0xFF -> -1
    lbu  x20, 20(x0)       # zero-extended byte 0xFF -> 255
    lh   x21, 20(x0)       # sign-extended half 0xFFFF -> -1
    lhu  x22, 20(x0)       # zero-extended half 0xFFFF -> 65535

end:
    jal  x0, end           # sit here forever; testbench stops at end
