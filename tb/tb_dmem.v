`timescale 1ns/1ps
// cache_controller wired to the real data_mem: proves the block port handshake
// completes (a miss refills, a dirty eviction reaches memory) rather than hanging.
module tb_dmem;
  localparam BLOCK_BITS = 256, ADDR_BITS = 32;
  reg clk = 0, reset = 1;
  always #5 clk = ~clk;

  reg cpu_data_in_valid = 0, cpu_write_read = 0;
  reg [31:0] cpu_data_in = 0, cpu_addr_in = 0;
  reg [1:0]  cpu_size = 2'b10;
  wire [31:0] cpu_data_out;
  wire cpu_ready_out, cpu_data_out_valid;

  wire mem_ready, mem_data_in_valid, mem_write_read, mem_addr_in_valid, mem_data_out_valid;
  wire [BLOCK_BITS-1:0] mem_data_in, mem_data_out;
  wire [ADDR_BITS-1:0]  mem_addr_in;
  integer errors = 0, i;

  cache_controller #(.ADDR_BITS(ADDR_BITS), .DATA_WIDTH(32), .BLOCK_BITS(BLOCK_BITS),
                     .WORD_OFF_BITS(3), .WB_FIFO_DEPTH(4))
  ctrl (.clk(clk), .reset(reset),
    .cpu_data_in_valid(cpu_data_in_valid), .cpu_write_read(cpu_write_read),
    .cpu_data_in(cpu_data_in), .cpu_size(cpu_size), .cpu_addr_in(cpu_addr_in),
    .cpu_data_out(cpu_data_out), .cpu_ready_out(cpu_ready_out),
    .cpu_data_out_valid(cpu_data_out_valid),
    .mem_ready(mem_ready), .mem_data_in_valid(mem_data_in_valid),
    .mem_data_in(mem_data_in), .mem_write_read(mem_write_read),
    .mem_addr_in(mem_addr_in), .mem_addr_in_valid(mem_addr_in_valid),
    .mem_data_out(mem_data_out), .mem_data_out_valid(mem_data_out_valid));

  data_mem #(.DATA_WIDTH(32), .BLOCK_BITS(BLOCK_BITS), .D_MEM_DEPTH(1024), .WORD_OFF_BITS(3))
  dmem (.clk(clk), .reset(reset),
    .mem_ready(mem_ready), .data_out_valid(mem_data_in_valid), .data_out(mem_data_in),
    .addr_in(mem_addr_in), .addr_in_valid(mem_addr_in_valid),
    .data_in(mem_data_out), .data_in_valid(mem_data_out_valid),
    .write_read(mem_write_read));

  task chk(input [255:0] name, input [31:0] got, exp);
    begin
      if (got === exp) $display("ok   %0s = %h", name, got);
      else begin $display("FAIL %0s: got %h exp %h", name, got, exp); errors = errors + 1; end
    end
  endtask

  // one cpu access, with a bounded wait so a hang is reported not waited on
  task cpu(input wr, input [31:0] a, d);
    integer t;
    begin
      @(negedge clk);
      cpu_write_read = wr; cpu_addr_in = a; cpu_data_in = d; cpu_data_in_valid = 1;
      @(negedge clk);
      t = 0;
      while (!cpu_ready_out && t < 400) begin @(negedge clk); t = t + 1; end
      if (t >= 400) begin
        $display("FAIL timeout: %s addr %h never accepted (block port hung)", wr?"write":"read", a);
        errors = errors + 1; $display("\n=== HUNG ===\n"); $finish;
      end
      cpu_data_in_valid = 0;
      t = 0;
      while (!cpu_data_out_valid && t < 400) begin @(negedge clk); t = t + 1; end
      if (t >= 400) begin
        $display("FAIL timeout: %s addr %h never completed (block port hung)", wr?"write":"read", a);
        errors = errors + 1; $display("\n=== HUNG ===\n"); $finish;
      end
    end
  endtask

  initial begin
    for (i = 0; i < 1024; i = i + 1) dmem.mem[i] = 32'hD0000000 + i;
    repeat (4) @(negedge clk); reset = 0; repeat (2) @(negedge clk);

    cpu(0, 32'h0000_0040, 0);   // miss -> refill block at word 16
    chk("refill word 16 (addr 0x40)", cpu_data_out, 32'hD0000010);
    cpu(0, 32'h0000_004C, 0);   // hit, word 19 of the same block
    chk("same block word 19 (0x4C)", cpu_data_out, 32'hD0000013);
    cpu(0, 32'h0000_0044, 0);
    chk("mid-block addr does not straddle", cpu_data_out, 32'hD0000011);

    // a SECOND refill: if data_out_valid is not a one cycle pulse the cache
    // latches the previous block the moment it enters M_PORT_READ_WAIT
    cpu(0, 32'h0000_0080, 0);
    chk("second refill word 32 (0x80)", cpu_data_out, 32'hD0000020);
    cpu(0, 32'h0000_0094, 0);
    chk("second refill word 37 (0x94)", cpu_data_out, 32'hD0000025);

    // word index 16384 must truncate into a 1024 word array -> word 0
    cpu(0, 32'h0001_0000, 0);
    chk("out of range addr wraps into array", cpu_data_out, 32'hD0000000);

    cpu(1, 32'h0000_0040, 32'hCAFE_0001);   // dirty it
    cpu(0, 32'h0000_0040, 0);
    chk("read back the store", cpu_data_out, 32'hCAFE_0001);

    // force eviction of that dirty block: 4 ways + enough conflicting sets
    cpu(0, 32'h0001_0040, 0); cpu(0, 32'h0002_0040, 0);
    cpu(0, 32'h0003_0040, 0); cpu(0, 32'h0004_0040, 0);
    cpu(0, 32'h0005_0040, 0);
    repeat (80) @(negedge clk);
    chk("dirty block written back to memory", dmem.mem[16], 32'hCAFE_0001);
    chk("neighbour word intact in memory",   dmem.mem[17], 32'hD0000011);

    if (errors == 0) $display("\n=== ALL CHECKS PASSED ===\n");
    else $display("\n=== %0d FAILURE(S) ===\n", errors);
    $finish;
  end
endmodule
