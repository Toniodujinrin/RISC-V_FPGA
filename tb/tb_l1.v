`timescale 1ns/1ps
module tb;
  localparam BLOCK_BITS = 256;  // 8 words
  reg clk = 0, reset = 1;
  reg write_read = 0, valid = 0;
  reg [31:0] addr = 0, data_in = 0;
  reg missed_valid_in = 0;
  reg [BLOCK_BITS-1:0] missed_block_in = 0;
  wire [31:0] data_out, evicted_address, miss_addr;
  wire output_valid, ready, evicted_valid, miss_valid;
  wire [BLOCK_BITS-1:0] evicted_block;
  integer errors = 0;

  cache #(.BLOCK_BITS(BLOCK_BITS), .WORD_OFF_BITS(3))
  dut(.clk(clk), .reset(reset), .write_read(write_read), .valid(valid),
    //size was added to cache on 23 Aug and never connected here, so every
    //access silently took the word path and all the byte checks failed
    .size(2'b00),
    .addr(addr), .data_in(data_in),
    .missed_valid_in(missed_valid_in), .missed_block_in(missed_block_in),
    .data_out(data_out), .output_valid(output_valid), .ready(ready),
    .evicted_block(evicted_block), .evicted_address(evicted_address),
    .evicted_valid(evicted_valid), .miss_valid(miss_valid), .miss_addr(miss_addr));

  always #5 clk = ~clk;

  // capture eviction as it pulses
  reg [BLOCK_BITS-1:0] ev_block_seen; reg [31:0] ev_addr_seen; reg ev_seen;
  always @(posedge clk) if(evicted_valid) begin
    ev_block_seen <= evicted_block; ev_addr_seen <= evicted_address; ev_seen <= 1;
  end

  task do_req(input wr, input [31:0] a, input [31:0] d,
              input [BLOCK_BITS-1:0] refill);
    begin
      @(negedge clk);
      while(!ready) @(negedge clk);
      valid=1; write_read=wr; addr=a; data_in=d;
      @(negedge clk); valid=0;
      // serve a miss if one is signalled
      fork begin : svc
        integer guard; guard=0;
        while(!output_valid && guard<50) begin
          if(miss_valid) begin
            @(negedge clk); missed_block_in=refill; missed_valid_in=1;
            @(negedge clk); missed_valid_in=0;
          end else @(negedge clk);
          guard=guard+1;
        end
        if(guard>=50) begin $display("TIMEOUT addr=%h", a); errors=errors+1; end
      end join
    end
  endtask

  task chk(input [31:0] got, input [31:0] exp, input [255:0] what);
    begin
      if(got !== exp) begin
        $display("FAIL %0s: got %h exp %h", what, got, exp); errors=errors+1;
      end else $display("ok   %0s = %h", what, got);
    end
  endtask

  reg [BLOCK_BITS-1:0] blk;
  integer i;
  initial begin
    ev_seen = 0;
    repeat(3) @(negedge clk); reset = 0; repeat(2) @(negedge clk);

    // 1. write miss to set 1, word 2, byte 0 -> addr 0x0000_0048
    blk = 0; for(i=0;i<16;i=i+1) blk[i*32 +: 32] = 32'hA000_0000 + i;
    do_req(1, 32'h0000_0048, 32'hDEAD_BEEF, blk);
    chk(miss_addr_lat, 32'h0000_0040, "write miss addr block-aligned");

    // 2. read back that byte -> hit, byte 0 of word 2, zero extended
    do_req(0, 32'h0000_0048, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_00EF, "read back stored byte (hit)");

    // 3. byte 1 of word 2 must still hold the refilled data (0xA0000002 -> 0x00)
    do_req(0, 32'h0000_0049, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_0000, "untouched byte 1 of word 2 from refill");

    // 4. word_index selects the word: word 1, byte 0 of the refill = 0x01
    do_req(0, 32'h0000_0044, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_0001, "word_index picks word 1 of the refill");

    // 5. byte_index selects the byte: word 0, byte 3 of the refill = 0xA0
    do_req(0, 32'h0000_0043, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_00A0, "byte_index picks byte 3 of word 0");

    // 6. store to word 0 byte 1, data taken from the matching lane of data_in
    //RISC-V SB takes the byte from rs2[7:0] regardless of the address. this
    //stimulus predates that fix and still put the byte in the addressed lane
    do_req(1, 32'h0000_0041, 32'h0000_0055, {BLOCK_BITS{1'bx}});
    do_req(0, 32'h0000_0041, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_0055, "byte store merged, other bytes intact");
    do_req(0, 32'h0000_0043, 32'h0, {BLOCK_BITS{1'bx}});
    chk(data_out, 32'h0000_00A0, "neighbouring byte 3 untouched by the store");

    // 7. fill the other 3 ways of set 1, then a 5th block -> evict the dirty LRU
    for(i=1;i<4;i=i+1) begin
      blk = {BLOCK_BITS{1'b0}}; blk[31:0] = 32'hB000_0000 + i;
      do_req(0, 32'h0000_0040 + (i<<13), 32'h0, blk);
    end
    ev_seen = 0;
    blk = {BLOCK_BITS{1'b0}}; blk[31:0] = 32'hC000_0000;
    do_req(0, 32'h0000_0040 + (4<<13), 32'h0, blk);
    if(!ev_seen) begin $display("FAIL: no eviction on 5th block into set 1"); errors=errors+1; end
    else begin
      chk(ev_addr_seen, 32'h0000_0040, "evicted address = the dirty way");
      chk(ev_block_seen[31:0], 32'hA000_5500, "evicted word 0 holds the merged byte");
      chk(ev_block_seen[2*32 +: 32], 32'hA00000EF, "evicted word 2 holds the first store");
    end

    if(errors==0) $display("\n=== ALL CHECKS PASSED ===");
    else $display("\n=== %0d FAILURE(S) ===", errors);
    $finish;
  end

  // latch miss_addr for checking
  reg [31:0] miss_addr_lat;
  always @(posedge clk) if(miss_valid) miss_addr_lat <= miss_addr;

  initial begin #20000; $display("global timeout"); $finish; end
endmodule
