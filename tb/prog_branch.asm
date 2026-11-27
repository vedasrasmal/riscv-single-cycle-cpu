# prog_branch.asm — branches (taken and not taken, all six kinds)
# and jumps (JAL, JALR). Expected final state (tb/cpu_branch_tb.v):
#   x1=5  x3=15 (loop 1+2+3+4+5)  x4=7  x5=8  x8=11  x9=12
#   x10=13  x11=14  x13=15  x16=16
#   x12 = address of the instruction after `jal x12, skip7`
#   x15 = address of the instruction after `jalr x15, 0(x14)`
#   (both return addresses are read off the assembler listing)

    addi x1, x0, 0        # counter = 0
    addi x2, x0, 5        # limit = 5
    addi x3, x0, 0        # sum = 0
loop:
    addi x1, x1, 1        # counter++
    add  x3, x3, x1       # sum += counter
    blt  x1, x2, loop     # loop while counter < 5
    # counter = 5, sum = 15 here

    beq  x1, x2, skip1    # taken (5 == 5)
    addi x4, x0, 99       # skipped
skip1:
    addi x4, x0, 7        # x4 = 7
    bne  x1, x2, skip2    # not taken (5 == 5)
    addi x5, x0, 8        # x5 = 8
skip2:
    addi x6, x0, -3       # x6 = -3
    addi x7, x0, 2        # x7 = 2
    blt  x6, x7, skip3    # taken (-3 < 2, signed)
    addi x8, x0, 99       # skipped
skip3:
    addi x8, x0, 11       # x8 = 11
    bltu x7, x6, skip4    # taken (2 < 0xFFFFFFFD, unsigned)
    addi x9, x0, 99       # skipped
skip4:
    addi x9, x0, 12       # x9 = 12
    bge  x7, x6, skip5    # taken (2 >= -3, signed)
    addi x10, x0, 99      # skipped
skip5:
    addi x10, x0, 13      # x10 = 13
    bgeu x6, x7, skip6    # taken (0xFFFFFFFD >= 2, unsigned)
    addi x11, x0, 99      # skipped
skip6:
    addi x11, x0, 14      # x11 = 14

    jal  x12, skip7       # x12 = return address, jump to skip7
    addi x13, x0, 99      # skipped
skip7:
    addi x13, x0, 15      # x13 = 15

    # JALR: build the target address of skip8 with AUIPC + ADDI.
    auipc x14, 0          # x14 = PC of this auipc
    addi x14, x14, 16     # +16 bytes -> address of skip8
    jalr x15, 0(x14)      # x15 = return address, jump to skip8
    addi x16, x0, 99      # skipped
skip8:
    addi x16, x0, 16      # x16 = 16

end:
    jal  x0, end           # sit here forever; testbench stops at end
