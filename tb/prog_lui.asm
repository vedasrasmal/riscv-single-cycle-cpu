# prog_lui.asm — LUI/AUIPC, register and immediate shifts, signed and
# unsigned compares. Expected final state (tb/cpu_lui_tb.v):
#   x1=0x12345678  x3=0x34567800  x4=0x00123456  x5=0x00123456
#   x6=0xFFFFFF00  x7=0xFFFFFFF0  x8=0x0FFFFFF0
#   x9=1  x10=0  x11=0  x12=1
#   x14=0x91A2B3C0  x15=0x02468ACF  x16=0xFFFFFFE0
#   x17=0xFFFFF000  x18=0xFFFFEFFF
#   x2 = address of the `auipc x2, 0` instruction (from the listing)

    lui  x1, 0x12345      # x1 = 0x12345000
    addi x1, x1, 0x678    # x1 = 0x12345678
    auipc x2, 0           # x2 = PC of this instruction
    slli x3, x1, 8        # 0x12345678 << 8 = 0x34567800
    srli x4, x1, 8        # 0x12345678 >> 8 = 0x00123456
    srai x5, x1, 8        # positive, same as SRLI = 0x00123456
    addi x6, x0, -256     # x6 = 0xFFFFFF00 (-256)
    srai x7, x6, 4        # -256 >> 4 (arith) = -16 = 0xFFFFFFF0
    srli x8, x6, 4        # 0xFFFFFF00 >> 4 (logical) = 0x0FFFFFF0
    slt  x9, x6, x1       # -256 < 0x12345678 signed -> 1
    sltu x10, x6, x1      # 0xFFFFFF00 < 0x12345678 unsigned -> 0
    slt  x11, x1, x6      # 0x12345678 < -256 signed -> 0
    sltu x12, x1, x6      # 0x12345678 < 0xFFFFFF00 unsigned -> 1
    addi x13, x0, 3       # shift amount = 3
    sll  x14, x1, x13     # 0x12345678 << 3 = 0x91A2B3C0
    srl  x15, x1, x13     # 0x12345678 >> 3 = 0x02468ACF
    sra  x16, x6, x13     # -256 >> 3 (arith) = -32 = 0xFFFFFFE0
    lui  x17, 0xFFFFF     # x17 = 0xFFFFF000
    addi x18, x17, -1     # x18 = 0xFFFFEFFF

end:
    jal  x0, end           # sit here forever; testbench stops at end
