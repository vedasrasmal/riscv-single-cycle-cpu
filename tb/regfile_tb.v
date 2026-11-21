//=============================================================================
// regfile_tb.v — Self-checking testbench for the RV32I register file
// RV32I single-cycle CPU.
//
// Every case checks the read data against expected values. Any mismatch
// prints FAIL and is counted; at the end a summary is printed and the
// simulation exits non-zero ($fatal) if anything failed.
//
// Run with Icarus Verilog:
//   iverilog -o sim/regfile_tb.vvp rtl/regfile.v tb/regfile_tb.v
//   vvp sim/regfile_tb.vvp
//=============================================================================

`timescale 1ns / 1ps

module regfile_tb;

    reg         clk = 0;
    reg         reg_write;
    reg  [4:0]  rs1, rs2, rd;
    reg  [31:0] write_data;
    wire [31:0] read_data1, read_data2;

    integer errors = 0;
    integer total  = 0;

    regfile dut (
        .clk(clk),
        .reg_write(reg_write),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .write_data(write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    // 10 ns clock.
    always #5 clk = ~clk;

    // Check one case: compare both read ports against expected values.
    task check;
        input [31:0] exp1;
        input [31:0] exp2;
        input [8*28-1:0] tname;
        begin
            total = total + 1;
            #1;
            if (read_data1 !== exp1 || read_data2 !== exp2) begin
                errors = errors + 1;
                $display("FAIL %-28s : rs1=x%0d rs2=x%0d -> rd1=%h (exp %h), rd2=%h (exp %h)",
                         tname, rs1, rs2, read_data1, exp1, read_data2, exp2);
            end else begin
                $display("PASS %-28s : rd1=%h rd2=%h", tname, read_data1, read_data2);
            end
        end
    endtask

    // Write one value: present it, wait for the clock edge, let it land.
    task write_reg;
        input [4:0]  waddr;
        input [31:0] wdata;
        begin
            rd = waddr; write_data = wdata; reg_write = 1'b1;
            @(posedge clk); #1;
            reg_write = 1'b0;
        end
    endtask

    initial begin
        $display("=== RV32I register file testbench ===");
        reg_write = 0; rs1 = 0; rs2 = 0; rd = 0; write_data = 0;

        // ---- power-on state: everything reads 0 -------------------------
        rs1 = 5'd0; rs2 = 5'd5;
        check(32'd0, 32'd0, "RESET x0=0, x5=0");

        // ---- one write, read back on both ports --------------------------
        write_reg(5'd5, 32'hDEADBEEF);
        rs1 = 5'd5; rs2 = 5'd5;
        check(32'hDEADBEEF, 32'hDEADBEEF, "WRITE x5, read both ports");

        // ---- second register, both ports at once -------------------------
        write_reg(5'd31, 32'h12345678);
        rs1 = 5'd5; rs2 = 5'd31;
        check(32'hDEADBEEF, 32'h12345678, "x5 and x31 together");

        // ---- x0 is hardwired: write is dropped, read stays 0 ------------
        write_reg(5'd0, 32'hFFFFFFFF);
        rs1 = 5'd0; rs2 = 5'd5;
        check(32'd0, 32'hDEADBEEF, "WRITE x0 ignored, x5 kept");

        // ---- overwrite with a new value ----------------------------------
        write_reg(5'd5, 32'd0);
        rs1 = 5'd5; rs2 = 5'd31;
        check(32'd0, 32'h12345678, "OVERWRITE x5 with 0");

        // ---- reg_write = 0: no write happens -----------------------------
        rd = 5'd7; write_data = 32'hAAAAAAAA; reg_write = 1'b0;
        @(posedge clk); #1;
        rs1 = 5'd7; rs2 = 5'd31;
        check(32'd0, 32'h12345678, "reg_write=0, x7 stays 0");

        // ---- write x7 properly, then check both ports again --------------
        write_reg(5'd7, 32'hAAAAAAAA);
        rs1 = 5'd7; rs2 = 5'd5;
        check(32'hAAAAAAAA, 32'd0, "WRITE x7, x5 still 0");

        // ---- x1 and x2 (the usual operand pair) --------------------------
        write_reg(5'd1, 32'd5);
        write_reg(5'd2, 32'd7);
        rs1 = 5'd1; rs2 = 5'd2;
        check(32'd5, 32'd7, "x1=5, x2=7 together");

        // ---- write to x1 does not disturb x2 ------------------------------
        write_reg(5'd1, 32'hFFFFFFFF);
        rs1 = 5'd1; rs2 = 5'd2;
        check(32'hFFFFFFFF, 32'd7, "x1 changed, x2 untouched");

        // ---- read of x0 on the second port too ---------------------------
        rs1 = 5'd31; rs2 = 5'd0;
        check(32'h12345678, 32'd0, "x31 kept, x0 reads 0");

        // ---- summary -----------------------------------------------------
        $display("--------------------------------------------------");
        $display("REGFILE TEST SUMMARY: %0d/%0d passed", total - errors, total);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1, "regfile testbench failed");
        end
    end

endmodule
