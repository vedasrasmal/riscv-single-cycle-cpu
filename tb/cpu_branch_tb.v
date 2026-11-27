//=============================================================================
// cpu_branch_tb.v — Full-CPU test: branches (all six kinds, taken and
// not taken) and jumps JAL/JALR (program tb/prog_branch.asm).
// RV32I single-cycle CPU.
//
// The loop sums 1+2+3+4+5 = 15, which checks that BLT takes the branch
// exactly four times and falls through on the fifth. Each later branch
// is written so the skipped instruction holds 99: if a branch goes the
// wrong way, the wrong value lands in the register and the check fails.
// JAL and JALR are checked both for the jump (the 99 is skipped) and
// for the return address written to rd.
//
// Run from the repo root with Icarus Verilog:
//   iverilog -o sim/cpu_branch_tb.vvp rtl/*.v tb/cpu_branch_tb.v
//   vvp sim/cpu_branch_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module cpu_branch_tb;

    reg clk = 0;
    reg rst = 1;

    integer errors = 0;
    integer total  = 0;
    integer cycles = 0;

    // Address of the `end:` label in prog_branch.asm (assembler listing).
    localparam END_PC = 32'h00000084;

    riscv_cpu #(.HEX_FILE("tb/prog_branch.hex")) dut (
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
        $display("=== RV32I CPU branch/jump test ===");

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
            $fatal(1, "CPU branch test timed out");
        end
        $display("reached end after %0d cycles", cycles);

        // Loop: counter 1..5, sum 1+2+3+4+5.
        check_reg(5'd1, 32'd5,           "x1 counter = 5");
        check_reg(5'd2, 32'd5,           "x2 limit = 5");
        check_reg(5'd3, 32'd15,          "x3 sum = 15");
        // BEQ taken, BNE not taken.
        check_reg(5'd4, 32'd7,           "x4 BEQ taken");
        check_reg(5'd5, 32'd8,           "x5 BNE not taken");
        // Signed compare with a negative number.
        check_reg(5'd6, 32'hFFFFFFFD,    "x6 = -3");
        check_reg(5'd7, 32'd2,           "x7 = 2");
        check_reg(5'd8, 32'd11,          "x8 BLT taken");
        // Unsigned compare: 2 < 0xFFFFFFFD.
        check_reg(5'd9, 32'd12,          "x9 BLTU taken");
        check_reg(5'd10, 32'd13,         "x10 BGE taken");
        check_reg(5'd11, 32'd14,         "x11 BGEU taken");
        // JAL: return address is the instruction after the jal (0x0068),
        // and the skipped instruction (99) never ran.
        check_reg(5'd12, 32'h00000068,   "x12 JAL return addr");
        check_reg(5'd13, 32'd15,         "x13 after JAL");
        // JALR: auipc gave x14 = 0x70, then +16 made it the skip8
        // address 0x80 — the value checked here is the final x14.
        check_reg(5'd14, 32'h00000080,   "x14 JALR target addr");
        check_reg(5'd15, 32'h0000007C,   "x15 JALR return addr");
        check_reg(5'd16, 32'd16,         "x16 after JALR");

        $display("--------------------------------------------------");
        $display("CPU BRANCH TEST SUMMARY: %0d/%0d passed",
                 total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "CPU branch testbench failed");
        end
    end

endmodule
