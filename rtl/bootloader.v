module bootloader
#(
  parameter DATA_WIDTH = 32,
  parameter BLOCK_BITS = 256,
  parameter CLK_SPEED  = 50000000
)
(
  input  clk, 
  input reset, 
  input rx, 
  output tx, 
  output reg boot_active, 

  //instruction memory word write port
  output [DATA_WIDTH-1:0] imem_waddr, 
  output [DATA_WIDTH-1:0] imem_wdata, 
  output reg imem_we, 

  //sdram cpu-side port. accepts on (dram_valid && dram_ready) in NORMAL_IDLE
  output [DATA_WIDTH-1:0] dram_addr, 
  output [BLOCK_BITS-1:0] dram_wdata,
  output reg dram_valid, 
  output reg dram_write_read, 
  input dram_ready 
);

  localparam BLOCK_BYTES = BLOCK_BITS/8;    //32
  localparam BLOCK_WORDS = BLOCK_BITS/32;   //8

  wire tick;
  reg tx_start, tx_start_next;
  reg [7:0] tx_din, tx_din_next;
  reg [31:0] pyld_buff, pyld_buff_next;             //word assembly, imem
  reg [BLOCK_BITS-1:0] blk_buff, blk_buff_next;     //block assembly, dram
  reg [7:0] dest_mem, dest_mem_next; 
  reg [31:0] start_addr, start_addr_next; 
  reg [31:0] mem_addr, mem_addr_next; 
  reg [3:0] current_state, next_state;
  reg [7:0] check_sum, check_sum_next;              //payload WORD count
  reg [7:0] check_sum_ctr, check_sum_ctr_next;      //payload words seen
  reg [1:0] pyld_cntr, pyld_cntr_next;              //byte index within a word
  reg [7:0] sum_acc, sum_acc_next;                  //running sum of payload
  reg sum_ok, sum_ok_next; 
  reg [1:0] hdr_ctr, hdr_ctr_next;                  //start_addr byte index
  reg [7:0] record_len, record_len_next; 
  reg [7:0] record_ctr, record_ctr_next; 
  reg [31:0] prg_byte_cntr, prg_byte_cntr_next;     //byte offset in record
  reg imem_we_next; 
  reg dram_valid_next, dram_write_read_next; 

  wire tx_busy;
  wire tx_valid; 
  wire rx_valid;
  wire [7:0] rx_out; 

  reg boot_active_next; 

  assign imem_wdata = pyld_buff; 
  assign imem_waddr = mem_addr; 
  assign dram_addr  = mem_addr; 
  assign dram_wdata = blk_buff; 

  localparam DEST_IMEM = 8'h00; 
  localparam DEST_DRAM = 8'h02; 

  localparam ACK_MSG = 8'h06; 
  localparam NAK_MSG = 8'h15; 

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin
      boot_active <= 1; 
      tx_start <= 0;
      tx_din  <= 0; 
      dest_mem <= 0;
      start_addr <= 0; 
      pyld_buff <= 0; 
      blk_buff <= 0; 
      check_sum <= 0; 
      sum_acc <= 0; 
      sum_ok <= 0; 
      hdr_ctr <= 0; 
      current_state <= CHECK_SUM_BYTE; 
      check_sum_ctr <= 0; 
      pyld_cntr <= 0; 
      prg_byte_cntr <= 0; 
      mem_addr <= 0; 
      imem_we <= 0; 
      dram_valid <= 0; 
      dram_write_read <= 0; 
      record_ctr <= 0; 
      record_len <= 0; 
    end 
    else 
    begin 
      boot_active <= boot_active_next; 
      tx_start <= tx_start_next;
      tx_din <= tx_din_next;
      dest_mem <= dest_mem_next; 
      start_addr <= start_addr_next; 
      pyld_buff <= pyld_buff_next; 
      blk_buff <= blk_buff_next; 
      check_sum <= check_sum_next; 
      sum_acc <= sum_acc_next; 
      sum_ok <= sum_ok_next; 
      hdr_ctr <= hdr_ctr_next; 
      current_state <= next_state; 
      check_sum_ctr <= check_sum_ctr_next;
      pyld_cntr <= pyld_cntr_next;
      prg_byte_cntr <= prg_byte_cntr_next;
      mem_addr <= mem_addr_next; 
      imem_we <= imem_we_next; 
      dram_valid <= dram_valid_next; 
      dram_write_read <= dram_write_read_next; 
      record_ctr <= record_ctr_next; 
      record_len <= record_len_next; 
    end
  end 

  localparam PYLD_WRD_WIDTH = 3'd4; 
  /////////////////////////////////////////////////
  //Header Description: 
  //byte 0: check_sum   -- payload BYTE count for this record 
  //byte 1: record_len -- n records in the whole transfer 
  //byte 2: dest_mem   -- 0x00 imem, 0x02 dram 
  //byte 3: start_addr[7:0],   byte 4: start_addr[15:8],
  //byte 5: start_addr[23:16], byte 6: start_addr[31:24] 
  //then check_sum payload bytes, then one byte: 8-bit wrapping sum of them.
  //one reply byte per record, after the sum: ACK_MSG or NAK_MSG.
  /////////////////////////////////////////////////////

  //states 
  localparam CHECK_SUM_BYTE    = 4'd0;
  localparam RECORD_LENGTH    = 4'd1;
  localparam DEST_MEM_BYTE    = 4'd2; 
  localparam START_ADDR_BYTES = 4'd3; 
  localparam PROGRAM_BYTES    = 4'd4; 
  localparam DRAM_WRITE       = 4'd5; 
  localparam SUM_BYTE         = 4'd6; 
  localparam REPLY            = 4'd7; 
  localparam FINISHED         = 4'd8; 

  always@(*)
  begin 
    boot_active_next = boot_active; 
    tx_start_next = 0; 
    tx_din_next = tx_din; 
    dest_mem_next = dest_mem; 
    start_addr_next = start_addr; 
    pyld_buff_next = pyld_buff;
    blk_buff_next = blk_buff; 
    check_sum_next = check_sum; 
    sum_acc_next = sum_acc; 
    sum_ok_next = sum_ok; 
    hdr_ctr_next = hdr_ctr; 
    record_len_next = record_len; 
    check_sum_ctr_next = check_sum_ctr; 
    pyld_cntr_next = pyld_cntr; 
    mem_addr_next = mem_addr;
    imem_we_next = 0; 
    dram_valid_next = dram_valid; 
    dram_write_read_next = dram_write_read; 
    prg_byte_cntr_next = prg_byte_cntr; 
    record_ctr_next = record_ctr; 
    next_state = current_state; 
    case(current_state)
      CHECK_SUM_BYTE: 
      begin 
        if(rx_valid)
        begin 
          check_sum_next = rx_out; 
          sum_acc_next = 0; 
          check_sum_ctr_next = 0; 
          pyld_cntr_next = 0; 
          prg_byte_cntr_next = 0; 
          next_state = RECORD_LENGTH; 
        end 
      end

      RECORD_LENGTH:
      begin 
        if(rx_valid)
        begin 
          record_len_next = rx_out; 
          next_state = DEST_MEM_BYTE; 
        end 
      end 

      DEST_MEM_BYTE: 
      begin 
        if(rx_valid)
        begin 
          dest_mem_next = rx_out; 
          next_state = START_ADDR_BYTES; 
        end
      end 

      START_ADDR_BYTES: 
      begin 
        if(rx_valid)
        begin
          start_addr_next[8*hdr_ctr +: 8] = rx_out; 
          if(hdr_ctr == 2'd3) 
          begin 
            hdr_ctr_next = 0; 
            next_state = PROGRAM_BYTES; 
          end 
          else 
            hdr_ctr_next = hdr_ctr + 1'b1;
        end 
      end 

      PROGRAM_BYTES: 
      begin 
        if(rx_valid)
        begin 
          sum_acc_next = sum_acc + rx_out; 
          pyld_cntr_next = pyld_cntr + 1'b1; 

          //dram fills a 32 byte block, imem a single word
          if(dest_mem == DEST_DRAM)
            blk_buff_next[8*{check_sum_ctr[2:0], pyld_cntr} +: 8] = rx_out; 
          else 
            pyld_buff_next[8*pyld_cntr +: 8] = rx_out; 

          //every 4th byte completes a word: that is what check_sum counts
          if(pyld_cntr == PYLD_WRD_WIDTH-1)
          begin 
            pyld_cntr_next = 0; 
            check_sum_ctr_next = check_sum_ctr + 1'b1; 

            if(dest_mem == DEST_DRAM)
            begin 
              //8 words fill a block: hand it to the controller
              if(check_sum_ctr[2:0] == BLOCK_WORDS-1)
              begin 
                mem_addr_next = start_addr + prg_byte_cntr; 
                prg_byte_cntr_next = prg_byte_cntr + BLOCK_BYTES; 
                next_state = DRAM_WRITE; 
              end 
              else if(check_sum_ctr == check_sum-1)
                next_state = SUM_BYTE; 
            end 
            else 
            begin 
              mem_addr_next = start_addr + prg_byte_cntr; 
              prg_byte_cntr_next = prg_byte_cntr + 3'd4; 
              imem_we_next = (dest_mem == DEST_IMEM); 
              if(check_sum_ctr == check_sum-1)
                next_state = SUM_BYTE; 
            end 
          end 
        end
      end

      //hold the block write until the controller takes it. it accepts on
      //(dram_valid && dram_ready), then drops dram_ready itself
      DRAM_WRITE: 
      begin 
        dram_valid_next = 1'b1; 
        dram_write_read_next = 1'b1;    //1 = write
        //dram_valid is a register, so it is still low on the cycle we arrive.
        //qualifying on it stops an already-idle controller from looking like
        //an accept before the request was ever driven
        if(dram_valid && dram_ready)
        begin 
          dram_valid_next = 1'b0; 
          if(check_sum_ctr == check_sum)
            next_state = SUM_BYTE; 
          else 
            next_state = PROGRAM_BYTES; 
        end 
      end 

      SUM_BYTE: 
      begin 
        if(rx_valid)
        begin 
          sum_ok_next = (rx_out == sum_acc); 
          tx_din_next = (rx_out == sum_acc)? ACK_MSG : NAK_MSG; 
          tx_start_next = 1'b1; 
          next_state = REPLY; 
        end 
      end 

      //one reply per record. waiting on tx_valid means the stop bit is out
      //before anything downstream can steal the pin
      REPLY: 
      begin 
        if(tx_valid)
        begin 
          sum_acc_next = 0; 
          check_sum_ctr_next = 0; 
          pyld_cntr_next = 0; 
          prg_byte_cntr_next = 0; 
          if(!sum_ok)
            next_state = CHECK_SUM_BYTE;          //host retransmits this record
          else if(record_ctr == record_len-1)
          begin 
            record_ctr_next = 0; 
            next_state = FINISHED; 
          end 
          else 
          begin 
            record_ctr_next = record_ctr + 1'b1; 
            next_state = CHECK_SUM_BYTE; 
          end 
        end 
      end 

      FINISHED: 
      begin 
        boot_active_next = 0; 
      end 

      default: next_state = CHECK_SUM_BYTE; 
    endcase
  end 

  uart_tx
  #(
    .MAX_DATA_BITS(8), 
    .MAX_STOP_BITS(2)
  )
  TX (
     .clk(clk),
     .reset(reset), 
     .tx_start(tx_start),
     .tick(tick), 
     .data_bits(3'd7), 
     .stop_bits(2'd1), 
     .parity_en(1'b0), 
     .parity_type(1'b0), 
     .din(tx_din), 
     .output_valid(tx_valid), 
     .busy(tx_busy), 
     .tx(tx)
  ); 

  uart_rx
  #(
    .MAX_DATA_BITS(8), 
    .MAX_STOP_BITS(2)
  )
  RX (
    .clk(clk),
    .reset(reset), 
    .rx(rx),
    .tick(tick), 
    .data_bits(3'd7), 
    .stop_bits(2'd1), 
    .parity_en(1'b0),
    .parity_type(1'b0), 
    .rx_en(boot_active), 
    .data_out_valid(rx_valid), 
    .parity_err(), 
    .busy(), 
    .data_out(rx_out)
  ); 

  uart_tick_gen
  #(
    .CLOCK_SPEED(CLK_SPEED)
  )
  TICK_GEN (
    .clk(clk),
    .reset(reset), 
    .tick(tick)
  ); 
endmodule 




module uart_tick_gen
#(
  parameter 
  CLOCK_SPEED = 50000000
)
(
  input clk, reset, 
  output reg tick
); 
  
  localparam B_115200_BR = CLOCK_SPEED/(21'd1843200); 
  localparam TICK_COUNT_WIDTH = $clog2(B_115200_BR); 
  reg [TICK_COUNT_WIDTH-1:0] tick_count; 
  
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      tick <= 0; 
      tick_count <= 0;
    end 
    else 
    begin 
      if(tick_count == B_115200_BR-1)
      begin 
        tick <= 1'b1; 
        tick_count <= 0;
      end 
      else 
      begin
        tick_count <= tick_count + 1; 
        tick <= 1'b0; 
      end
    end
  end
endmodule

