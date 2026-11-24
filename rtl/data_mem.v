//=============================================================================
// data_mem.v — RV32I Data Memory (byte/half/word loads and stores)
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// 256 words (1 KiB) of byte-addressable memory. The CPU gives it a byte
// address (the ALU result); addr[9:2] picks the word and addr[1:0] picks
// the byte inside it.
//
// Design choice: load size and sign/zero extension are handled HERE,
// inside the memory, driven by funct3 — so the CPU only has to pass
// funct3 through and select the memory output on a load. The alternative
// (raw word out, extension in the CPU) would spread the same logic
// across two modules; keeping it here keeps the CPU wiring simple and
// the extension logic testable in one place.
//
//   funct3 | load            | store
//   -------|-----------------|---------------------------
//   3'b000 | LB  sign-extend | SB  write data[7:0]
//   3'b001 | LH  sign-extend | SH  write data[15:0]
//   3'b010 | LW  full word   | SW  write data[31:0]
//   3'b100 | LBU zero-extend | (same as SB — funct3[2] set)
//   3'b101 | LHU zero-extend | (same as SH)
//
// Stores write only the addressed bytes: the other bytes of the word
// are left untouched, so a byte store next to a halfword store does not
// clobber its neighbour (tested in the arithmetic program).
//
// Reads are combinational (a load's data is available in the same cycle
// the address appears). Writes are synchronous, on the rising clock
// edge, only when mem_write is high. mem_read gates the read output to
// zero when the CPU is not loading — the value on the read port is only
// meaningful for a load anyway.
//
// The memory starts cleared to zero. Programs are expected to use
// aligned addresses for halfword and word accesses; a misaligned
// halfword store at an odd byte offset would write across the word
// boundary incorrectly, so aligned access is a documented limit.
//=============================================================================

`timescale 1ns / 1ps

module data_mem #(
    parameter DEPTH = 256 // words (1 KiB)
) (
    input  wire        clk,        // writes happen on posedge
    input  wire [31:0] addr,      // byte address (ALU result)
    input  wire [31:0] write_data,// data to store (from rs2)
    input  wire [2:0]  funct3,    // load/store size + signedness
    input  wire        mem_write, // 1 = store this cycle
    input  wire        mem_read,  // 1 = load this cycle (gates output)
    output reg  [31:0] read_data  // loaded value, already extended
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
    end

    // Word selected by the address; byte offset inside the word.
    wire [7:0]  word_index = addr[9:2];
    wire [1:0]  byte_off   = addr[1:0];
    wire [31:0] word       = mem[word_index];

    // ---- combinational read, with size + sign/zero extension ------------
    always @(*) begin
        if (!mem_read) begin
            read_data = 32'd0;
        end else begin
            case (funct3)
                // LB: sign-extend the selected byte.
                3'b000: begin
                    case (byte_off)
                        2'b00: read_data = {{24{word[7]}},  word[7:0]};
                        2'b01: read_data = {{24{word[15]}}, word[15:8]};
                        2'b10: read_data = {{24{word[23]}}, word[23:16]};
                        default: read_data = {{24{word[31]}}, word[31:24]};
                    endcase
                end
                // LH: sign-extend the selected halfword.
                3'b001: begin
                    case (byte_off)
                        2'b00:   read_data = {{16{word[15]}}, word[15:0]};
                        2'b10:   read_data = {{16{word[31]}}, word[31:16]};
                        default: read_data = 32'd0; // misaligned: not used
                    endcase
                end
                // LW: whole word.
                3'b010: read_data = word;
                // LBU: zero-extend the selected byte.
                3'b100: begin
                    case (byte_off)
                        2'b00: read_data = {24'd0, word[7:0]};
                        2'b01: read_data = {24'd0, word[15:8]};
                        2'b10: read_data = {24'd0, word[23:16]};
                        default: read_data = {24'd0, word[31:24]};
                    endcase
                end
                // LHU: zero-extend the selected halfword.
                3'b101: begin
                    case (byte_off)
                        2'b00:   read_data = {16'd0, word[15:0]};
                        2'b10:   read_data = {16'd0, word[31:16]};
                        default: read_data = 32'd0; // misaligned: not used
                    endcase
                end
                default: read_data = word;
            endcase
        end
    end

    // ---- synchronous write, only the addressed bytes ---------------------
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                // SB: write one byte.
                3'b000, 3'b100: begin
                    case (byte_off)
                        2'b00: mem[word_index][7:0]   <= write_data[7:0];
                        2'b01: mem[word_index][15:8]  <= write_data[7:0];
                        2'b10: mem[word_index][23:16] <= write_data[7:0];
                        default: mem[word_index][31:24] <= write_data[7:0];
                    endcase
                end
                // SH: write one halfword.
                3'b001, 3'b101: begin
                    case (byte_off)
                        2'b00: mem[word_index][15:0]  <= write_data[15:0];
                        2'b10: mem[word_index][31:16] <= write_data[15:0];
                        default: begin end // misaligned: not used
                    endcase
                end
                // SW: write the whole word.
                default: mem[word_index] <= write_data;
            endcase
        end
    end

endmodule
