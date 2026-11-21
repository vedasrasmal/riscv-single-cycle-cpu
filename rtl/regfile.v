//=============================================================================
// regfile.v — RV32I Register File
// RV32I single-cycle CPU (Vedas Rasmal, GHRCEM Pune)
//
// 32 registers x 32 bits. Register x0 is hardwired to zero: writes to x0
// are ignored and reads of x0 always return 0, exactly as the ISA requires.
//
//   - Two asynchronous read ports (rs1, rs2): the values are available in
//     the same cycle, which is what a single-cycle CPU needs (the ALU gets
//     its operands without waiting for a clock edge).
//   - One synchronous write port: the write happens on the rising clock
//     edge, only when reg_write is high. Writes to x0 are dropped.
//
// The registers start at zero (initial block). In real hardware the
// initial block is ignored by synthesis and registers power up to 0 on
// most FPGAs; the CPU never reads a register before writing it in any
// correct program, so this only matters for simulation.
//=============================================================================

`timescale 1ns / 1ps

module regfile (
    input  wire        clk,        // clock: writes happen on posedge
    input  wire        reg_write,  // 1 = write rd on this clock edge
    input  wire [4:0]  rs1,        // first read address
    input  wire [4:0]  rs2,        // second read address
    input  wire [4:0]  rd,         // write address
    input  wire [31:0] write_data, // value to write into rd
    output wire [31:0] read_data1, // value of rs1 (0 if rs1 == x0)
    output wire [31:0] read_data2  // value of rs2 (0 if rs2 == x0)
);

    // The 32 registers. regs[0] is never written; reads of it return 0
    // through the muxes below, so its stored value is irrelevant.
    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'd0;
    end

    // Synchronous write, x0 protected.
    always @(posedge clk) begin
        if (reg_write && (rd != 5'd0))
            regs[rd] <= write_data;
    end

    // Asynchronous reads, x0 hardwired to 0.
    assign read_data1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

endmodule
