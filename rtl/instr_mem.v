//=============================================================================
// instr_mem.v — RV32I Instruction Memory (read-only)
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// 256 words (1 KiB) of read-only memory. The contents are loaded from a
// hex file at simulation start with $readmemh, so a test program is just
// a text file of one 32-bit word per line — see tb/prog_*.hex and the
// assembler tb/asm.py that generates them.
//
// The CPU fetches with a byte address (the PC). Instructions are always
// word-aligned, so the low two address bits are ignored and addr[9:2]
// picks the word. A read is combinational: the instruction is available
// in the same cycle the PC changes, which is what a single-cycle CPU
// needs.
//
// Out-of-range addresses (above 1 KiB) wrap into the memory through the
// address bits used — a program that jumps out of range fetches whatever
// word those bits select, it never produces X. In simulation the memory
// starts as the loaded program; words past the end of the hex file read
// as x until written — $readmemh leaves unloaded words uninitialised,
// so the memory is first cleared to zero and the file is read on top.
//=============================================================================

`timescale 1ns / 1ps

module instr_mem #(
    parameter HEX_FILE = "tb/prog_arith.hex", // program to load
    parameter DEPTH    = 256                  // words (1 KiB)
) (
    input  wire [31:0] addr,  // byte address (the PC)
    output wire [31:0] instr  // instruction at that address
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP (addi x0, x0, 0) by default,
                                   // so unwritten words are harmless.
        $readmemh(HEX_FILE, mem);
    end

    // Word-aligned combinational read; addr[1:0] ignored.
    assign instr = mem[addr[9:2]];

endmodule
