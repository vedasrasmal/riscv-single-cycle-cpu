//=============================================================================
// cpu_arith_tb.v — Full-CPU test: arithmetic, logic, shifts, compares,
// and every load/store size (program tb/prog_arith.asm).
// RV32I single-cycle CPU.
//
// The CPU runs the program from instruction memory until the PC reaches
// the `end` label (a `jal x0, end` self-loop), then the testbench reads
// the registers and data memory through hierarchical references and
// checks them against the expected values written in prog_arith.asm.
// A VCD waveform of the whole run is written to sim/cpu_arith.vcd.
//
// Run from the repo root with Icarus Verilog:
//   iverilog -o sim/cpu_arith_tb.vvp rtl/*.v tb/cpu_arith_tb.v
//   vvp sim/cpu_arith_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module cpu_arith_tb;

    reg clk = 0;
    reg rst = 1;

    integer errors = 0;
    integer total  = 0;
    integer cycles = 0;

    // Address of the `end:` label in prog_arith.asm (see assembler listing).
    localparam END_PC = 32'h00000078;

    riscv_cpu #(.HEX_FILE("tb/prog_arith.hex")) dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    task check_reg;
        input [4:0]  r;
        input [31:0] exp;
        input [8*24-1:0] tname;
        begin
            total = total + 1;
            if (dut.u_regfile.regs[r] !== exp) begin
                errors = errors + 1;
                $display("FAIL %-24s : x%0d = %h (expected %h)",
                         tname, r, dut.u_regfile.regs[r], exp);
            end else begin
                $display("PASS %-24s : x%0d = %h", tname, r, exp);
            end
        end
    endtask

    task check_mem;
        input [7:0]  word; // word index in data memory
        input [31:0] exp;
        input [8*24-1:0] tname;
        begin
            total = total + 1;
            if (dut.u_dmem.mem[word] !== exp) begin
                errors = errors + 1;
                $display("FAIL %-24s : mem[%0d] = %h (expected %h)",
                         tname, word, dut.u_dmem.mem[word], exp);
            end else begin
                $display("PASS %-24s : mem[%0d] = %h", tname, word, exp);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/cpu_arith.vcd");
        $dumpvars(0, cpu_arith_tb);
        $display("=== RV32I CPU arithmetic/memory test ===");

        // Hold reset for two clocks, then let the CPU run.
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
            $fatal(1, "CPU arithmetic test timed out");
        end
        $display("reached end after %0d cycles", cycles);

        // ---- arithmetic / logic / shifts / compares ------------------------
        check_reg(5'd3,  32'd35,         "x3 = 10+25");
        check_reg(5'd4,  32'd15,         "x4 = 25-10");
        check_reg(5'd5,  32'd3,          "x5 = 35&15");
        check_reg(5'd6,  32'd47,         "x6 = 35|15");
        check_reg(5'd7,  32'd44,         "x7 = 35^15");
        check_reg(5'd8,  32'd40,         "x8 = 10<<2");
        check_reg(5'd9,  32'd12,         "x9 = 25>>1");
        check_reg(5'd10, 32'hFFFFFFFC,   "x10 = -8>>1 = -4");
        check_reg(5'd11, 32'd1,          "x11 = SLT(10<25)");
        check_reg(5'd12, 32'd0,          "x12 = SLTU(25<10)");
        // ---- loads (values stored, then loaded back) -----------------------
        check_reg(5'd13, 32'd35,         "x13 = lw mem[0]");
        check_reg(5'd14, 32'd15,         "x14 = lw mem[4]");
        check_reg(5'd15, 32'd35,         "x15 = lb mem[8]");
        check_reg(5'd16, 32'd10,         "x16 = lbu mem[9]");
        check_reg(5'd17, 32'd35,         "x17 = lh mem[12]");
        check_reg(5'd18, 32'hFFFFFFFF,   "x18 = -1");
        check_reg(5'd19, 32'hFFFFFFFF,   "x19 = lb sign-extend");
        check_reg(5'd20, 32'd255,        "x20 = lbu zero-extend");
        check_reg(5'd21, 32'hFFFFFFFF,   "x21 = lh sign-extend");
        check_reg(5'd22, 32'd65535,      "x22 = lhu zero-extend");
        // ---- data memory contents ------------------------------------------
        check_mem(8'd0, 32'd35,          "mem word 0 = 35");
        check_mem(8'd1, 32'd15,          "mem word 1 = 15");
        // Byte stores at 8 and 9 share word 2: 0x23 and 0x0A.
        check_mem(8'd2, 32'h00000A23,    "mem word 2 = bytes");
        check_mem(8'd3, 32'd35,          "mem word 3 = 35");
        check_mem(8'd4, 32'd0,           "mem word 4 = 0");
        check_mem(8'd5, 32'hFFFFFFFF,    "mem word 5 = -1");

        $display("--------------------------------------------------");
        $display("CPU ARITH TEST SUMMARY: %0d/%0d passed",
                 total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "CPU arithmetic testbench failed");
        end
    end

endmodule
