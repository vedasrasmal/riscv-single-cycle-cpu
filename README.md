# RV32I Single-Cycle CPU

A single-cycle RV32I CPU in Verilog, by Vedas Rasmal (3rd-year B.Tech ENTC, GHRCEM Pune). Every module lands only after its own testbench passes — nothing is added on trust.

## ALU (`rtl/alu.v`)

Combinational 32-bit ALU. Inputs: two 32-bit operands `a`, `b` and a 4-bit
`alu_ctrl`. Outputs: 32-bit `result` and a `zero` flag (1 when the result is
0 — later used by the branch logic).

### ALU control table

| `alu_ctrl` | Operation | Notes |
|------------|-----------|-------|
| `0000` | ADD | `a + b`, wraps mod 2^32 |
| `0001` | SUB | `a - b`, wraps mod 2^32 |
| `0010` | AND | bitwise AND |
| `0011` | OR | bitwise OR |
| `0100` | XOR | bitwise XOR |
| `0101` | SLL | logical left shift by `b[4:0]` |
| `0110` | SRL | logical right shift by `b[4:0]` (zero fill) |
| `0111` | SRA | arithmetic right shift by `b[4:0]` (sign fill) |
| `1000` | SLT | 1 if `a < b` (signed), else 0 |
| `1001` | SLTU | 1 if `a < b` (unsigned), else 0 |
| other | 0 | undefined control safely returns 0 |

Shift amount is always `b[4:0]` (RV32I shifts are modulo 32), so a shift by
32 behaves as a shift by 0. Encoding follows Harris & Harris, *Digital
Design and Computer Architecture* (RISC-V edition).

## Register file (`rtl/regfile.v`)

32 registers x 32 bits, two asynchronous read ports and one synchronous
write port (write on the rising clock edge, only when `reg_write` is high).
Register `x0` is hardwired to zero: writes to it are ignored and reads of
it always return 0.

## Immediate generator (`rtl/imm_gen.v`)

Gathers the scattered immediate bits of each instruction format and
sign-extends them to 32 bits. `imm_src` selects the format:

| `imm_src` | Format | Instructions |
|-----------|--------|--------------|
| `000` | I-type | ADDI, LW, JALR, ... |
| `001` | S-type | SW, SB, SH |
| `010` | B-type | BEQ, BNE, ... |
| `011` | U-type | LUI, AUIPC |
| `100` | J-type | JAL |

Branch and jump immediates already include their trailing 0 bit
(instructions are 2-byte aligned).

## Control unit (`rtl/control_unit.v`)

Decodes the opcode, funct3 and funct7 fields into the control signals
the datapath needs: register write, memory read/write, ALU source,
branch and jump, plus the 3-bit `imm_src` for the immediate generator.
A second decoder maps `alu_op` + funct3 + funct7[5] to the ALU control
code. Unknown opcodes produce all-zero signals — no write, no memory
access — instead of doing something undefined.

## Instruction memory (`rtl/instr_mem.v`)

256 words (1 KiB) of read-only memory, loaded from a hex file at
simulation start (`$readmemh`). The PC is a byte address and
`addr[9:2]` picks the word. Words past the end of the program are
pre-filled with NOPs, so running off the end executes NOPs instead of
producing X values.

## Data memory (`rtl/data_mem.v`)

256 words (1 KiB) of byte-addressable memory. Load size and sign/zero
extension are handled inside the memory, driven by `funct3`: LB/LH/LW
sign-extend, LBU/LHU zero-extend; SB/SH/SW write only the addressed
bytes, leaving neighbouring bytes untouched. Reads are combinational;
writes happen on the rising clock edge, only when `mem_write` is high.

## Top level (`rtl/riscv_cpu.v`)

Wires everything together into the single-cycle datapath: fetch, decode,
execute, memory access and write-back in one clock cycle. Next PC: JALR
goes to `(rs1 + imm)` with bit 0 cleared; JAL or a taken branch goes to
`PC + imm`; otherwise `PC + 4`. The branch decision uses the ALU zero
flag and result with the branch type from `funct3`.

## Test programs (`tb/prog_*.asm`, `tb/cpu_*_tb.v`)

Three small assembly programs exercise the whole CPU end to end:
arithmetic and memory (31 instructions), branches and jumps (34
instructions), and LUI/AUIPC/shifts (20 instructions). A tiny two-pass
assembler (`tb/asm.py`) turns each `.asm` file into the `.hex` file the
instruction memory loads. Each program has its own self-checking
testbench, which runs the program on the CPU and checks the final
register and memory values. The arithmetic run also dumps a VCD waveform
(`sim/cpu_arith.vcd`), viewable in GTKWave.

## How to run the tests

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/)
(`sudo apt install iverilog` on Ubuntu/Debian).

```sh
mkdir -p sim
iverilog -o sim/alu_tb.vvp rtl/alu.v tb/alu_tb.v
vvp sim/alu_tb.vvp
iverilog -o sim/regfile_tb.vvp rtl/regfile.v tb/regfile_tb.v
vvp sim/regfile_tb.vvp
iverilog -o sim/imm_gen_tb.vvp rtl/imm_gen.v tb/imm_gen_tb.v
vvp sim/imm_gen_tb.vvp
iverilog -o sim/control_unit_tb.vvp rtl/control_unit.v tb/control_unit_tb.v
vvp sim/control_unit_tb.vvp
python3 tb/asm.py tb/prog_arith.asm
iverilog -o sim/cpu_arith_tb.vvp rtl/riscv_cpu.v rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control_unit.v rtl/instr_mem.v rtl/data_mem.v tb/cpu_arith_tb.v
vvp sim/cpu_arith_tb.vvp
python3 tb/asm.py tb/prog_branch.asm
iverilog -o sim/cpu_branch_tb.vvp rtl/riscv_cpu.v rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control_unit.v rtl/instr_mem.v rtl/data_mem.v tb/cpu_branch_tb.v
vvp sim/cpu_branch_tb.vvp
python3 tb/asm.py tb/prog_lui.asm
iverilog -o sim/cpu_lui_tb.vvp rtl/riscv_cpu.v rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control_unit.v rtl/instr_mem.v rtl/data_mem.v tb/cpu_lui_tb.v
vvp sim/cpu_lui_tb.vvp
```

Each testbench (`tb/*.v`) is self-checking: it checks every case against
expected values, prints PASS/FAIL per case, and exits non-zero if anything
fails.

## Verified result

- Tool: Icarus Verilog 12.0 (stable), run 20 Nov 2026.
- Cases: every operation (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT,
  SLTU) plus edge cases — overflow wrap-around, SLT with negative numbers,
  SLTU unsigned comparison, SRA sign extension vs SRL zero fill, shifts by
  0, 31 and 32, zero flag set/clear, undefined control codes.
- Result: **47/47 checks passed, ALL TESTS PASSED** (see terminal output
  in the test run below).
- Register file: **10/10 checks passed** — power-on zeros, write/read on
  both ports, `x0` write ignored, overwrite, `reg_write = 0` blocks the
  write, neighbouring registers untouched (Icarus Verilog 12.0, 20 Nov 2026).
- Immediate generator: **19/19 checks passed** — self-checking, on real
  instruction encodings (Icarus Verilog 12.0, 20 Nov 2026).
- Control unit: **39/39 checks passed** — self-checking, all opcodes incl.
  branches, jumps and illegal → NOP (Icarus Verilog 12.0, 21 Nov 2026).
- Memories + top level: exercised by the three full-CPU programs,
  **59/59 checks passed** (arithmetic 26/26, branches 16/16,
  LUI/AUIPC/shifts 17/17), Icarus Verilog 12.0, 20 Nov 2026.
- Full CPU: **174/174 checks passed** — ALU 47/47, register file 10/10,
  immediate generator 19/19, control unit 39/39, arithmetic 26/26,
  branches 16/16, LUI/AUIPC/shifts 17/17 (Icarus Verilog 12.0,
  re-run 27 Nov 2026).

## License

MIT — see `LICENSE`.
