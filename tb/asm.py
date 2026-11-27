#!/usr/bin/env python3
"""asm.py — a tiny two-pass assembler for the RV32I subset this CPU runs.

Usage:  python3 tb/asm.py tb/prog_arith.asm
Writes tb/prog_arith.hex (one 32-bit word per line) and prints a listing
(address, machine word, source line) plus the label map, so expected
register values and end addresses can be read off for the testbenches.

Supported instructions (real RV32I only, no pseudos except `nop`):
  R-type: add sub sll slt sltu xor srl sra or and
  I-type: addi slti sltiu xori ori andi slli srli srai jalr
          lb lh lw lbu lhu
  S-type: sb sh sw
  B-type: beq bne blt bge bltu bgeu
  U-type: lui auipc
  J-type: jal
Labels (`loop:`) may be used as branch/jump targets (relative offset);
load/store/jalr immediates are numeric only. Registers are x0-x31
(zero/ra/sp/gp/tp also accepted). Immediates are decimal, 0x hex, or
negative. Lines starting with `#` are comments.
"""

import re
import sys

REGS = {"zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4}
for i in range(8):
    REGS[f"t{i}"] = 5 + i if i < 3 else 25 + i  # t0-t2 = x5-x7, t3-t6 = x28-x31
for i in range(12):
    REGS[f"s{i}"] = 8 + i if i < 2 else 16 + i  # s0-s1 = x8-x9, s2-s11 = x18-x27
for i in range(8):
    REGS[f"a{i}"] = 10 + i

R_OPS = {"add": (0b000, 0), "sub": (0b000, 1), "sll": (0b001, 0),
         "slt": (0b010, 0), "sltu": (0b011, 0), "xor": (0b100, 0),
         "srl": (0b101, 0), "sra": (0b101, 1), "or": (0b110, 0),
         "and": (0b111, 0)}
I_OPS = {"addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
         "ori": 0b110, "andi": 0b111}
SHIFT_OPS = {"slli": (0b001, 0), "srli": (0b101, 0), "srai": (0b101, 1)}
LOAD_OPS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORE_OPS = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCH_OPS = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101,
              "bltu": 0b110, "bgeu": 0b111}

OP_R = 0b0110011
OP_I = 0b0010011
OP_LOAD = 0b0000011
OP_STORE = 0b0100011
OP_BRANCH = 0b1100011
OP_JAL = 0b1101111
OP_JALR = 0b1100111
OP_LUI = 0b0110111
OP_AUIPC = 0b0010111


def reg(name):
    name = name.strip().lower()
    if name in REGS:
        return REGS[name]
    m = re.fullmatch(r"x(\d+)", name)
    if not m or not 0 <= int(m.group(1)) <= 31:
        raise ValueError(f"bad register '{name}'")
    return int(m.group(1))


def imm(text, bits, label=None, pc=None, unsigned=False):
    """Parse an immediate; a label name resolves to (target - pc).
    Signed by default; unsigned=True for U-type immediates (lui/auipc),
    which are a plain 20-bit field, not a sign-extended value."""
    if label is not None:
        value = label - pc
    else:
        text = text.strip()
        if re.fullmatch(r"-?0x[0-9a-fA-F]+", text):
            value = int(text, 16)
        elif re.fullmatch(r"-?\d+", text):
            value = int(text, 10)
        else:
            raise ValueError(f"bad immediate '{text}'")
    if unsigned:
        lo, hi = 0, (1 << bits) - 1
    else:
        lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= value <= hi:
        raise ValueError(f"immediate {value} out of range for {bits} bits")
    return value & ((1 << bits) - 1)


def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) \
        | (rd << 7) | opcode


def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) \
        | (rd << 7) | opcode


def enc_s(imm12, rs2, rs1, funct3, opcode):
    return (((imm12 >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (funct3 << 12) | ((imm12 & 0x1F) << 7) | opcode


def enc_b(imm13, rs2, rs1, funct3, opcode):
    return (((imm13 >> 12) & 1) << 31) | (((imm13 >> 5) & 0x3F) << 25) \
        | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) \
        | (((imm13 >> 1) & 0xF) << 8) | (((imm13 >> 11) & 1) << 7) | opcode


def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm21, rd, opcode):
    return (((imm21 >> 20) & 1) << 31) | (((imm21 >> 1) & 0x3FF) << 21) \
        | (((imm21 >> 11) & 1) << 20) | (((imm21 >> 12) & 0xFF) << 12) \
        | (rd << 7) | opcode


def parse_mem(text):
    """Parse 'offset(base)' -> (offset string, base register)."""
    m = re.fullmatch(r"(.+)\((.+)\)", text.strip())
    if not m:
        raise ValueError(f"bad memory operand '{text}'")
    return m.group(1), reg(m.group(2))


def assemble(lines):
    # Pass 1: collect labels and the instruction list with addresses.
    labels = {}
    prog = []  # (pc, op, args, source line)
    pc = 0
    for lineno, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        while ":" in line:
            label, rest = line.split(":", 1)
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", label):
                raise ValueError(f"line {lineno}: bad label '{label}'")
            if label in labels:
                raise ValueError(f"line {lineno}: duplicate label '{label}'")
            labels[label] = pc
            line = rest.strip()
            if not line:
                break
        if not line:
            continue
        parts = [p.strip() for p in re.split(r"[,\s]+", line) if p.strip()]
        prog.append((pc, parts[0].lower(), parts[1:], raw.strip()))
        pc += 4
    # Pass 2: encode.
    words = []
    for pc, op, args, src in prog:
        if op == "nop":
            words.append((pc, 0x00000013, src))
            continue
        if op in R_OPS:
            f3, f7bit = R_OPS[op]
            rd, rs1, rs2 = reg(args[0]), reg(args[1]), reg(args[2])
            words.append((pc, enc_r(f7bit << 5, rs2, rs1, f3, rd, OP_R), src))
        elif op in I_OPS:
            rd, rs1 = reg(args[0]), reg(args[1])
            words.append((pc, enc_i(imm(args[2], 12), rs1, I_OPS[op], rd,
                                   OP_I), src))
        elif op in SHIFT_OPS:
            # Shifts are I-type: imm[11:5] is funct7 (0000000, or
            # 0100000 for SRAI), imm[4:0] is the shift amount.
            f3, f7bit = SHIFT_OPS[op]
            rd, rs1 = reg(args[0]), reg(args[1])
            shamt = imm(args[2], 5)
            imm12 = ((f7bit << 5) << 5) | shamt
            words.append((pc, enc_i(imm12, rs1, f3, rd, OP_I), src))
        elif op in LOAD_OPS:
            rd = reg(args[0])
            off, rs1 = parse_mem(args[1])
            words.append((pc, enc_i(imm(off, 12), rs1, LOAD_OPS[op], rd,
                                   OP_LOAD), src))
        elif op in STORE_OPS:
            rs2 = reg(args[0])
            off, rs1 = parse_mem(args[1])
            words.append((pc, enc_s(imm(off, 12), rs2, rs1, STORE_OPS[op],
                                   OP_STORE), src))
        elif op in BRANCH_OPS:
            rs1, rs2 = reg(args[0]), reg(args[1])
            target = args[2]
            if target in labels:
                off = imm(None, 13, labels[target], pc)
            else:
                off = imm(target, 13)
            words.append((pc, enc_b(off, rs2, rs1, BRANCH_OPS[op],
                                   OP_BRANCH), src))
        elif op == "lui":
            rd = reg(args[0])
            words.append((pc, enc_u(imm(args[1], 20, unsigned=True), rd,
                                   OP_LUI), src))
        elif op == "auipc":
            rd = reg(args[0])
            words.append((pc, enc_u(imm(args[1], 20, unsigned=True), rd,
                                   OP_AUIPC), src))
        elif op == "jal":
            rd = reg(args[0])
            target = args[1]
            if target in labels:
                off = imm(None, 21, labels[target], pc)
            else:
                off = imm(target, 21)
            words.append((pc, enc_j(off, rd, OP_JAL), src))
        elif op == "jalr":
            # jalr rd, offset(rs1): target = rs1 + offset, bit 0 cleared.
            rd = reg(args[0])
            off, rs1 = parse_mem(args[1])
            words.append((pc, enc_i(imm(off, 12), rs1, 0b000, rd,
                                   OP_JALR), src))
        else:
            raise ValueError(f"pc 0x{pc:04x}: unknown instruction '{op}'")
    return words, labels


def main():
    if len(sys.argv) != 2:
        print("usage: asm.py <program.asm>")
        sys.exit(2)
    src_path = sys.argv[1]
    out_path = src_path.rsplit(".", 1)[0] + ".hex"
    with open(src_path) as f:
        lines = f.readlines()
    words, labels = assemble(lines)
    with open(out_path, "w") as f:
        for _, w, _ in words:
            f.write(f"{w:08x}\n")
    print(f"{len(words)} instructions -> {out_path}")
    for pc, w, src in words:
        print(f"  0x{pc:04x}: {w:08x}  {src}")
    print("labels:")
    for name, addr in sorted(labels.items(), key=lambda kv: kv[1]):
        print(f"  {name}: 0x{addr:04x} ({addr})")


if __name__ == "__main__":
    main()
