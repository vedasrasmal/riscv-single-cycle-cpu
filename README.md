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

## How to run the tests

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/)
(`sudo apt install iverilog` on Ubuntu/Debian).

```sh
mkdir -p sim
iverilog -o sim/alu_tb.vvp rtl/alu.v tb/alu_tb.v
vvp sim/alu_tb.vvp
iverilog -o sim/regfile_tb.vvp rtl/regfile.v tb/regfile_tb.v
vvp sim/regfile_tb.vvp
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

## License

MIT — see `LICENSE`.
