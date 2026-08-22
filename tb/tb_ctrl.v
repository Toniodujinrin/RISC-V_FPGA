`timescale 1ns/1ps
// exercises the write back path: evictions must reach memory even when the
// write back buffer fills up and forces a drain of the buffer.
module tb_ctrl;
  localparam BLOCK_BITS = 512;
  localparam ADDR_BITS  = 32;
  localparam FIFO_DEPTH = 2;      // deliberately tiny so it can be filled

  reg clk = 0, reset = 1;
  reg cpu_data_in_valid = 0, cpu_write_read = 0;
  reg [31:0] cpu_data_in = 0, cpu_addr_in = 0;
  wire [31:0] cpu_data_out;
  wire cpu_ready_out, cpu_data_out_valid;

  wire mem_ready = 1'b1;
  reg mem_data_in_valid = 0;
  reg [BLOCK_BITS-1:0] mem_data_in = 0;
  wire mem_write_read, mem_addr_in_valid, mem_data_out_valid;
  wire [ADDR_BITS-1:0] mem_addr_in;
  wire [BLOCK_BITS-1:0] mem_data_out;

  integer errors = 0;

  cache_controller #(.ADDR_BITS(ADDR_BITS), .DATA_WIDTH(32),
                     .BLOCK_BITS(BLOCK_BITS), .WB_FIFO_DEPTH(FIFO_DEPTH))
  dut (.clk(clk), .reset(reset),
    .cpu_data_in_valid(cpu_data_in_valid), .cpu_write_read(cpu_write_read),
    .cpu_data_in(cpu_data_in), .cpu_addr_in(cpu_addr_in),
    .cpu_data_out(cpu_data_out), .cpu_ready_out(cpu_ready_out),
    .cpu_data_out_valid(cpu_data_out_valid),
    .mem_ready(mem_ready), .mem_data_in_valid(mem_data_in_valid),
    .mem_data_in(mem_data_in), .mem_write_read(mem_write_read),
    .mem_addr_in(mem_addr_in), .mem_addr_in_valid(mem_addr_in_valid),
    .mem_data_out(mem_data_out), .mem_data_out_valid(mem_data_out_valid));

  always #5 clk = ~clk;

  // ---- memory model -------------------------------------------------------
  integer wb_count = 0, rd_count = 0;
  reg [31:0] wb_addr_log  [0:63];
  reg [31:0] wb_word0_log [0:63];
  reg read_pending = 0;
  reg [31:0] read_addr = 0;
  integer read_delay = 0;

  always @(posedge clk) begin
    if(reset) begin
      mem_data_in_valid <= 0; read_pending <= 0;
    end else begin
      mem_data_in_valid <= 0;
      if(mem_addr_in_valid && mem_ready) begin
        if(mem_write_read) begin
          if(!mem_data_out_valid) begin
            $display("FAIL: write request without mem_data_out_valid"); errors=errors+1;
          end
          wb_addr_log[wb_count]  <= mem_addr_in;
          wb_word0_log[wb_count] <= mem_data_out[31:0];
          wb_count <= wb_count + 1;
          $display("  [mem] write back addr=%h word0=%h", mem_addr_in, mem_data_out[31:0]);
        end else begin
          if(read_pending) begin
            $display("FAIL: overlapping read requests"); errors=errors+1;
          end
          read_addr <= mem_addr_in; read_pending <= 1; read_delay <= 4;
          rd_count <= rd_count + 1;
          $display("  [mem] read req  addr=%h", mem_addr_in);
        end
      end
      if(read_pending) begin
        if(read_delay > 0) read_delay <= read_delay - 1;
        else begin
          mem_data_in <= {16{read_addr}};   // every word == the block address
          mem_data_in_valid <= 1;
          read_pending <= 0;
        end
      end
    end
  end

  // ---- properties ---------------------------------------------------------
  reg drain_seen = 0, full_seen = 0, held_seen = 0;
  always @(posedge clk) if(!reset) begin
    if(dut.drain_mode)       drain_seen <= 1;
    if(dut.fifo_full)        full_seen  <= 1;
    if(dut.evict_hold_valid) held_seen  <= 1;
    // the requested behaviour: while draining, a miss must not take the memory port
    if(dut.drain_mode && mem_addr_in_valid && mem_ready && !mem_write_read) begin
      $display("FAIL: read request issued while draining the write back buffer");
      errors = errors + 1;
    end
    // an eviction must never be dropped on the floor
    if(dut.fifo_cache_evicted_valid && dut.evict_hold_valid) begin
      $display("FAIL: second eviction arrived while one was still held");
      errors = errors + 1;
    end
  end

  // ---- cpu driver ---------------------------------------------------------
  task cpu_store(input [31:0] a, input [31:0] d);
    begin
      @(negedge clk);
      while(!cpu_ready_out) @(negedge clk);
      cpu_addr_in=a; cpu_data_in=d; cpu_write_read=1; cpu_data_in_valid=1;
      @(negedge clk); cpu_data_in_valid=0;
      begin : wait_done
        integer g; g=0;
        while(!cpu_data_out_valid && g<2000) begin @(negedge clk); g=g+1; end
        if(g>=2000) begin $display("FAIL: store to %h never completed", a); errors=errors+1; end
      end
    end
  endtask

  // starve the fifo of memory-port grants once the test asks for it, so that
  // evictions pile up and the buffer actually reaches full
  reg starve_fifo = 0;
  always @(*) if(starve_fifo) force dut.fifo_grant = 1'b0; else release dut.fifo_grant;

  // let the buffer stay starved for a while after drain mode engages, then release
  initial begin
    wait(dut.drain_mode === 1'b1);
    $display("-- drain mode engaged, miss is paused; holding the starve for 30 cycles --");
    repeat(30) @(posedge clk);
    if(cpu_data_out_valid) begin
      $display("FAIL: store completed while the buffer was meant to be draining");
      errors = errors + 1;
    end
    $display("-- releasing the fifo grant, buffer should drain then the miss resume --");
    starve_fifo = 0;
  end

  integer i, j, hit_idx, found;
  initial begin
    repeat(3) @(negedge clk); reset=0; repeat(2) @(negedge clk);

    // stores to one set with distinct tags (tag starts at bit 13).
    // the first 4 fill the ways, every one after that evicts a dirty line.
    for(i=0; i<4; i=i+1)
      cpu_store(32'h0000_0040 + (i<<13), 32'h0000_0000 + i);

    $display("-- ways filled, starving the write back buffer of memory grants --");
    starve_fifo = 1;

    // 3 more stores: two evictions fill the depth-2 buffer, the third has
    // nowhere to go and must halt the miss until the buffer has drained
    for(i=4; i<7; i=i+1)
      cpu_store(32'h0000_0040 + (i<<13), 32'h0000_0000 + i);

    // and a few more once everything has recovered
    for(i=7; i<10; i=i+1)
      cpu_store(32'h0000_0040 + (i<<13), 32'h0000_0000 + i);

    repeat(400) @(negedge clk);

    $display("\nwrite backs seen: %0d (expected 6), read requests: %0d (expected 10)",
             wb_count, rd_count);
    if(wb_count != 6) begin $display("FAIL: lost or duplicated write backs"); errors=errors+1; end
    if(rd_count != 10) begin $display("FAIL: wrong number of refills"); errors=errors+1; end
    if(!full_seen)  begin $display("FAIL: buffer never filled, test was vacuous"); errors=errors+1; end
    else $display("ok   write back buffer reached full");
    if(!held_seen)  begin $display("FAIL: eviction was never held, test was vacuous"); errors=errors+1; end
    else $display("ok   eviction held while the buffer was full");
    if(!drain_seen) begin $display("FAIL: drain mode never engaged, test was vacuous"); errors=errors+1; end
    else $display("ok   drain mode engaged, paused the miss, and released");

    // every evicted line must reach memory exactly once, carrying its store
    for(i=0; i<6; i=i+1) begin
      found = 0; hit_idx = 0;
      for(j=0; j<wb_count; j=j+1)
        if(wb_addr_log[j] == 32'h0000_0040 + (i<<13)) begin found=found+1; hit_idx=j; end
      if(found != 1) begin
        $display("FAIL: block %h written back %0d times (expected 1)",
                 32'h0000_0040 + (i<<13), found); errors=errors+1;
      end else if(wb_word0_log[hit_idx] !== (((32'h0000_0040 + (i<<13)) & 32'hFFFFFF00) | i)) begin
        $display("FAIL: block %h word0=%h, store byte missing",
                 32'h0000_0040 + (i<<13), wb_word0_log[hit_idx]); errors=errors+1;
      end else
        $display("ok   block %h written back once, word0=%h (store byte merged)",
                 32'h0000_0040 + (i<<13), wb_word0_log[hit_idx]);
    end

    if(errors==0) $display("\n=== ALL CHECKS PASSED ===");
    else $display("\n=== %0d FAILURE(S) ===", errors);
    $finish;
  end

  initial begin #500000; $display("FAIL: global timeout (deadlock?)"); $finish; end
endmodule
