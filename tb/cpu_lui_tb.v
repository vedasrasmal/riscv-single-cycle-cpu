//=============================================================================
// cpu_lui_tb.v — Full-CPU test: LUI/AUIPC, immediate and register shifts,
// signed and unsigned compares (program tb/prog_lui.asm).
// RV32I single-cycle CPU.
//
// Checks that LUI builds a value in the top 20 bits, AUIPC returns the
// address of its own instruction, shifts fill correctly (SRA keeps the
// sign, SRL fills with zero), and SLT/SLTU disagree exactly where
// signed and unsigned order differ (the same pair, -256 vs 0x12345678).
//
// Run from the repo root with Icarus Verilog:
//   iverilog -o sim/cpu_lui_tb.vvp rtl/*.v tb/cpu_lui_tb.v
//   vvp sim/cpu_lui_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module cpu_lui_tb;

    reg clk = 0;
    reg rst = 1;

    integer errors = 0;
    integer total  = 0;
    integer cycles = 0;

    // Address of the `end:` label in prog_lui.asm (assembler listing).
    localparam END_PC = 32'h0000004C;

    riscv_cpu #(.HEX_FILE("tb/prog_lui.hex")) dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    task check_reg;
        input [4:0]  r;
        input [31:0] exp;
        input [8*28-1:0] tname;
        begin
            total = total + 1;
            if (dut.u_regfile.regs[r] !== exp) begin
                errors = errors + 1;
                $display("FAIL %-28s : x%0d = %h (expected %h)",
                         tname, r, dut.u_regfile.regs[r], exp);
            end else begin
                $display("PASS %-28s : x%0d = %h", tname, r, exp);
            end
        end
    endtask

    initial begin
        $display("=== RV32I CPU LUI/AUIPC/shift test ===");

        repeat (2) @(posedge clk);
        #1 rst = 0;

        while (dut.pc !== END_PC && cycles < 2000) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end
        if (dut.pc !== END_PC) begin
            $display("FAIL: CPU did not reach end (pc=%h after %0d cycles)",
                     dut.pc, cycles);
            $fatal(1, "CPU LUI test timed out");
        end
        $display("reached end after %0d cycles", cycles);

        check_reg(5'd1,  32'h12345678,   "x1 = 0x12345678");
        // AUIPC at address 0x08 returns its own PC.
        check_reg(5'd2,  32'h00000008,   "x2 = AUIPC address");
        check_reg(5'd3,  32'h34567800,   "x3 = x1 << 8");
        check_reg(5'd4,  32'h00123456,   "x4 = x1 >> 8 logical");
        check_reg(5'd5,  32'h00123456,   "x5 = x1 >> 8 arith (+ve)");
        check_reg(5'd6,  32'hFFFFFF00,   "x6 = -256");
        check_reg(5'd7,  32'hFFFFFFF0,   "x7 = -256 >> 4 = -16");
        check_reg(5'd8,  32'h0FFFFFF0,   "x8 = 0xFFFFFF00 >> 4");
        check_reg(5'd9,  32'd1,          "x9 = SLT(-256 < x1)");
        check_reg(5'd10, 32'd0,          "x10 = SLTU(x6 < x1)");
        check_reg(5'd11, 32'd0,          "x11 = SLT(x1 < x6)");
        check_reg(5'd12, 32'd1,          "x12 = SLTU(x1 < x6)");
        check_reg(5'd14, 32'h91A2B3C0,   "x14 = x1 << 3 (reg)");
        check_reg(5'd15, 32'h02468ACF,   "x15 = x1 >> 3 (reg)");
        check_reg(5'd16, 32'hFFFFFFE0,   "x16 = -256 >> 3 = -32");
        check_reg(5'd17, 32'hFFFFF000,   "x17 = LUI 0xFFFFF");
        check_reg(5'd18, 32'hFFFFEFFF,   "x18 = x17 - 1");

        $display("--------------------------------------------------");
        $display("CPU LUI TEST SUMMARY: %0d/%0d passed",
                 total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "CPU LUI testbench failed");
        end
    end

endmodule
