
//apb slave wrapper over uart_tx and uart_rx modules (synchronous uart)
//byte wide registers at consecutive byte addresses, so software uses lb/sb. the
//bridge puts a store in the byte lane the address selects and shifts a load
//back down out of it, so both are undone here with the same lane shift
module uart 
#(
  parameter 
  MAX_STOP_BITS = 2, 
  MAX_DATA_BITS = 8, 
  APB_DATA_WIDTH = 32
)
(
 input clk, reset,
 input rx, 
 output tx, 
 input PSEL, 
 input PWRITE, 
 input PENABLE, 
 input [APB_DATA_WIDTH-1:0] PWDATA, 
 input [APB_DATA_WIDTH-1:0] PADDR, 
 input [3:0] PSTRB, 
 output reg PREADY, 
 output reg PSLVERR, 
 output reg [APB_DATA_WIDTH-1:0] PRDATA
); 
 wire tick; 
 localparam FILE_SIZE = 8; 
 localparam FILE_ADDR_WIDTH = 3; 
 //register file 8bits 
 reg [7:0] file [0:FILE_SIZE-1]; 
 
 localparam TX_DATA_REG = 3'b000;  
 //f[0] -- 0x0 -> TX_DATA 
 
 localparam RX_DATA_REG = 3'b001; 
 //f[1] -- 0x1 -> RX_DATA
 
 localparam CONTROL_REG = 3'b010; 
 //f[2][0] -- 0x2 -> PARITY_EN 
 //f[2][1] -- 0x2 -> UART_ENABLE 
 //f[2][2] -- 0x2 -> RX_ENABLE 
 //f[2][3] -- 0x2 -> TX_ENABLE
 //f[2][4] -- 0x2 -> RX_OVERRUN
 //default: xxx00000
 //RX_OVERRUN is set by hardware, not software: it lives here rather than in
 //STATUS so that it can be written, STATUS being read only. it holds the
 //receiver off until software clears it
 
 localparam CONFIG_REG = 3'b011; 
 //f[3][1:0] -- 0x3 -> BAUDE_RATE_IDX 
 //f[3][4:2] -- 0X3 -> DATA_BITS 
 //f[3][6:5] -- 0x3 -> STOP_BITS
 //f[3][7] -- 0x3 -> PARITY_TYPE 
 //default: 00111101
 //DATA_BITS is the bit count minus one, the only encoding that reaches 8 in a 3
 //bit field. STOP_BITS is a plain count. the default is 8 data bits, 1 stop bit
 
 localparam STATUS_REG = 3'b100;//read only 
 //f[4][0] -- 0x4 -> TX_BUSY 
 //f[4][1] -- 0x4 -> RX_BUSY
 //f[4][2] -- 0x4 -> TX_EMPTY 
 //f[4][3] -- Ox4 -> RX_VALID 
 //f[4][4] -- Ox4 -> PARITY_ERROR 
 //default: xxx00000 
 //read back off the live flags rather than out of the file

 localparam IRQ_REG = 3'b101;  
 //f[5][0] -- 0x5 -> RX_IRQ_ENABLE 
 //f[5][1] -- 0x5 -> TX_IRQ_ENABLE
 //default: xxxxxx00 

 //apb decode. the access is taken on the first cycle of the access phase only,
 //PREADY being registered holds PENABLE up for a second one. PSTRB says nothing
 //the address does not already say, every register being a byte, so it is unused
 wire access, wr, rd, mapped, read_only; 
 wire [FILE_ADDR_WIDTH-1:0] offset; 
 wire [4:0] lane; 
 wire [7:0] wdata; 
 assign access = PSEL && PENABLE && !PREADY; 
 assign wr = access && PWRITE; 
 assign rd = access && !PWRITE; 
 assign offset = PADDR[FILE_ADDR_WIDTH-1:0]; 
 assign lane = {PADDR[1:0], 3'b000}; 
 assign wdata = PWDATA[lane +: 8]; 
 //the only two ways a transfer can go wrong: a hole in the 4K window, or a
 //write to a read only register
 assign mapped = (PADDR[11:FILE_ADDR_WIDTH] == 0) && (offset <= IRQ_REG); 
 assign read_only = (offset == RX_DATA_REG) || (offset == STATUS_REG); 

 wire uart_en, tx_en, rx_en, overrun; 
 assign uart_en = file[CONTROL_REG][1]; 
 assign tx_en = uart_en && file[CONTROL_REG][3]; 
 assign overrun = file[CONTROL_REG][4]; 
 assign rx_en = uart_en && file[CONTROL_REG][2] && !overrun; 

 reg tx_empty, rx_valid, parity_error; 
 wire tx_busy, rx_busy, tx_done, rx_data_valid, rx_parity_err; 
 wire [7:0] rx_data, status; 
 assign status = {3'b000, parity_error, rx_valid, tx_empty, rx_busy, tx_busy}; 

 reg tx_start; 
 always@(posedge clk, posedge reset)
 begin 
    if(reset)
    begin 
      file[0] <= 0; 
      file[1] <= 0; 
      file[2] <= 0; 
      file[3] <= 8'b00111101; 
      file[4] <= 0; 
      file[5] <= 0; 
      file[6] <= 0; 
      file[7] <= 0; 
      PREADY <= 0; 
      PSLVERR <= 0; 
      PRDATA <= 0; 
      tx_start <= 0; 
      tx_empty <= 1'b1; 
      rx_valid <= 0; 
      parity_error <= 0; 
    end 
    else 
    begin 
      PREADY <= 0; 
      PSLVERR <= 0; 
      tx_start <= 0; //one cycle pulse, the transmitter latches din with it
      if(access)
      begin 
        PREADY <= 1; 
        PSLVERR <= !mapped || (PWRITE && read_only); 
        if(!PWRITE)
          PRDATA <= {{(APB_DATA_WIDTH-8){1'b0}}, 
                     (offset == STATUS_REG)? status : file[offset]} << lane; 
      end 
      if(wr && mapped && !read_only)
      begin 
        case(offset)
        TX_DATA_REG:
        begin 
          file[TX_DATA_REG] <= wdata; 
          if(tx_en && tx_empty)
          begin 
            tx_start <= 1'b1; 
            tx_empty <= 1'b0; 
          end 
        end
        CONTROL_REG: file[CONTROL_REG] <= wdata; 
        CONFIG_REG:  file[CONFIG_REG] <= wdata; 
        IRQ_REG:     file[IRQ_REG] <= wdata; 
        endcase
      end 

      if(tx_done)
        tx_empty <= 1'b1; 

      //a frame that fails its parity check never reaches RX_DATA: rx_valid
      //stays low and the sticky error bit is all software sees of it
      if(rx_data_valid)
      begin 
        if(rx_valid)
          //the unread byte is the one software is waiting for, so it stays and
          //the new frame is what gets lost. the set beats a software write to
          //CONTROL in the same cycle, an overrun is never dropped on the floor
          file[CONTROL_REG][4] <= 1'b1; 
        else 
        begin 
          file[RX_DATA_REG] <= rx_data; 
          rx_valid <= 1'b1; 
        end 
      end 
      else if(rd && (offset == RX_DATA_REG))
        rx_valid <= 1'b0; //the read consumes the byte

      if(rx_parity_err)
        parity_error <= 1'b1; 
      else if(rd && (offset == STATUS_REG))
        parity_error <= 1'b0; 
    end 
 end

 uart_tx
 #(
    .MAX_DATA_BITS(MAX_DATA_BITS), 
    .MAX_STOP_BITS(MAX_STOP_BITS)
 )
 TX
 (
    .clk(clk),
    .reset(reset), 
    .tx_start(tx_start),
    .tick(tick), 
    .din(file[TX_DATA_REG]),
    .data_bits(file[CONFIG_REG][4:2]), 
    .stop_bits(file[CONFIG_REG][6:5]), 
    .parity_en(file[CONTROL_REG][0]), 
    .parity_type(file[CONFIG_REG][7]), 
    .output_valid(tx_done), 
    .busy(tx_busy), 
    .tx(tx)
 ); 

 uart_rx
 #(
   .MAX_DATA_BITS(MAX_DATA_BITS), 
   .MAX_STOP_BITS(MAX_STOP_BITS)
 )
 RX
 (
    .clk(clk),
    .reset(reset), 
    .rx(rx),
    .tick(tick), 
    .data_bits(file[CONFIG_REG][4:2]), 
    .stop_bits(file[CONFIG_REG][6:5]), 
    .parity_en(file[CONTROL_REG][0]),
    .parity_type(file[CONFIG_REG][7]), 
    .data_out_valid(rx_data_valid), 
    .data_out(rx_data), 
    .parity_err(rx_parity_err), 
    .busy(rx_busy), 
    .rx_en(rx_en)
 ); 
  
 
 tick_gen
 #(
    .MAX_TICK_RATE(307200), 
    .CLOCK_SPEED(50000000)
 )
 TICK 
 (
    .clk(clk),
    .reset(reset), 
    .baud_rate_idx(file[CONFIG_REG][1:0]), 
    .tick(tick)
 );
endmodule 


module uart_tx
#(
  parameter 
  MAX_DATA_BITS = 8, 
  MAX_STOP_BITS = 2
)
(
  input wire clk, reset, 
  input wire tx_start, tick, 
  input wire [$clog2(MAX_DATA_BITS)-1:0] data_bits, 
  input wire [$clog2(MAX_STOP_BITS+1)-1:0] stop_bits, 
  input wire parity_en, parity_type, 
  input wire [7:0] din, 
  output reg output_valid, 
  output wire busy, 
  output wire tx
); 

  localparam IDLE = 3'd0; 
  localparam START = 3'd1; 
  localparam DATA = 3'd2; 
  localparam PARITY = 3'd3; 
  localparam STOP = 3'd4; 
  
  reg [2:0] current_state, next_state; 
  reg [3:0] s_reg, s_next; 
  reg [2:0] n_reg, n_next; 
  reg [$clog2(MAX_STOP_BITS+1)-1:0] sb_reg, sb_next; //stop bit counter
  reg [7:0] b_reg, b_next; 
  reg o_reg, o_next; //running parity of the data bits
  reg tx_reg, tx_next; 

  assign tx = tx_reg; 
  assign busy = (current_state != IDLE); 

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      current_state <= IDLE; 
      s_reg <= 0; 
      n_reg <= 0; 
      sb_reg <= 0; 
      b_reg <= 0; 
      o_reg <= 0; 
      tx_reg <= 1'b1; 
    end
    else
    begin 
      current_state <= next_state; 
      s_reg <= s_next;
      n_reg <= n_next; 
      sb_reg <= sb_next; 
      b_reg <= b_next; 
      o_reg <= o_next; 
      tx_reg <= tx_next; 
    end
  end

  always@(*)
  begin 
    next_state = current_state; 
    output_valid = 1'b0; 
    s_next = s_reg; 
    n_next = n_reg; 
    sb_next = sb_reg; 
    b_next = b_reg; 
    o_next = o_reg; 
    tx_next = tx_reg; 
    
    case(current_state)
      IDLE:
      begin 
        tx_next = 1'b1; 
        if(tx_start)
        begin 
          next_state = START; 
          s_next = 0; 
          o_next = 0; 
          b_next = din; 
        end
      end
      START:
      begin 
        tx_next = 1'b0; 
        if(tick)
          if(s_reg == 15)
          begin 
            next_state = DATA; 
            s_next = 0; 
            n_next = 0;
          end 
          else 
            s_next = s_reg + 1; 
      end 
      DATA: 
      begin 
        tx_next = b_reg[0]; 
        if(tick)
          if(s_reg == 15)
          begin 
            s_next = 0; 
            b_next = b_reg >> 1; 
            o_next = o_reg ^ b_reg[0]; 
            if(n_reg == data_bits)
            begin 
              sb_next = 0; 
              next_state = parity_en? PARITY : STOP; 
            end
            else 
              n_next = n_reg + 1; 
          end
          else 
            s_next = s_reg + 1; 
      end 
      PARITY: 
      begin 
        //o_reg is 1 for an odd number of ones in the data, so the odd parity
        //bit is the one that makes the total odd -- its complement
        tx_next = parity_type? ~o_reg : o_reg; 
        if(tick)
          if(s_reg == 15)
          begin 
            next_state = STOP; 
            s_next = 0; 
          end
          else 
            s_next = s_reg + 1; 
      end 
      STOP: 
      begin 
        tx_next = 1'b1; 
        if(tick)
          if(s_reg == 15)
          begin 
            s_next = 0; 
            if(sb_reg == stop_bits-2'd1)
            begin 
              next_state = IDLE; 
              output_valid = 1'b1; 
            end 
            else 
              sb_next = sb_reg + 1; 
          end
          else 
            s_next = s_reg + 1; 
      end 
    endcase 
  end
endmodule 


module uart_rx
#(
  parameter 
  MAX_DATA_BITS = 8, 
  MAX_STOP_BITS = 2
)
(
  input clk, reset, 
  input rx, tick, 
  input [$clog2(MAX_DATA_BITS)-1:0] data_bits, 
  input [$clog2(MAX_STOP_BITS+1)-1:0] stop_bits, 
  input parity_en,
  input parity_type, 
  input rx_en, 
  output reg data_out_valid, 
  output reg parity_err, 
  output wire busy, 
  output wire [7:0] data_out
); 

  //states 
  localparam IDLE   = 3'b000;
  localparam START  = 3'b001;
  localparam DATA   = 3'b010;
  localparam PARITY = 3'b011;
  localparam STOP   = 3'b100;

  //signal declaration 
  reg [2:0] current_state , next_state; 
  reg [3:0] s_reg, s_next; //4 bit counter 
  reg [$clog2(MAX_DATA_BITS)-1:0] n_reg, n_next; //databit counter 
  reg [7:0] b_reg, b_next;  //shift register 
  reg o_reg, o_next; //odd counter 
  reg pe_reg, pe_next; //partiy error 
  reg [$clog2(MAX_STOP_BITS+1)-1:0] sb_reg, sb_next; //stop bit counter

  assign data_out = b_reg; 
  assign busy = (current_state != IDLE); 
 
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      current_state <= IDLE; 
      s_reg <= 0; 
      n_reg <= 0;
      b_reg <= 0; 
      o_reg <= 0; 
      pe_reg <= 0; 
      sb_reg <= 0; 
    end 
    else 
    begin 
      current_state <= next_state; 
      s_reg <= s_next; 
      n_reg <= n_next; 
      b_reg <= b_next;
      o_reg <= o_next; 
      pe_reg <= pe_next; 
      sb_reg <= sb_next; 
    end 
  end 

  always@(*)
  begin 
    next_state = current_state; 
    data_out_valid = 1'b0; 
    parity_err = 1'b0; 
    s_next = s_reg; 
    n_next = n_reg; 
    b_next = b_reg; 
    o_next = o_reg; 
    pe_next = pe_reg;
    sb_next = sb_reg; 
    case(current_state)
      IDLE: 
        if(~rx & rx_en)
        begin 
          next_state = START; 
          s_next = 0;
          sb_next = 0; 
          n_next = 0; 
          o_next = 0; 
          pe_next = 0; 
          b_next = 0; 
        end 
      START: 
        if(tick)
          if(s_reg == 7)
          begin 
            next_state = DATA; 
            s_next = 0; 
            n_next = 0; 
          end 
          else 
            s_next = s_reg + 1; 
      DATA: 
        if(tick)
          if(s_reg == 15)
          begin 
            s_next = 0; 
            b_next = {rx, b_reg[7:1]};
            o_next = o_reg^rx; 
            if(n_reg == data_bits)
            begin 
              //a frame narrower than 8 bits stops short of the bottom of the
              //shift register, so pull it down to bit 0
              b_next = b_next >> (3'd7 - data_bits); 
              if(parity_en)
                next_state = PARITY; 
              else
                next_state = STOP; 
            end 
            else 
              n_next = n_reg + 1; 
          end
          else  
            s_next = s_reg + 1;
      PARITY: 
        if(tick)
          if(s_reg == 15)
          begin 
            s_next = 0; 
            next_state = STOP; 
            if(parity_type)//odd parity
              //o_reg contains if sequence was odd
              //o_reg == 1 -> odd 
              //o_reg == 0 -> even 
              //o_reg == parity bit -> fail for odd parity 
              //o_reg != parity biy -> fail for even parity
              pe_next = o_reg == rx; 
            else
              pe_next = o_reg != rx; 
          end
          else 
              s_next = s_reg + 1; 
      STOP: 
        if(tick)
          if(s_reg == 15)
            begin 
              s_next = 0; 
              if(sb_reg == stop_bits-2'd1)
              begin
                next_state = IDLE; 
                //data out only valid if parity check fails
                //or parity not enabled, because pe_reg is
                //0 by default 
                data_out_valid = ~pe_reg;
                parity_err = pe_reg; 
                pe_next = 0; 
              end 
              else 
                sb_next = sb_reg + 1; 
            end
          else 
            s_next = s_reg + 1; 
    endcase 
  end 

  endmodule 


module tick_gen
#(
  parameter 
  MAX_TICK_RATE = 307200, 
  CLOCK_SPEED = 50000000
)
(
  input clk, reset, 
  input [1:0] baud_rate_idx, 
  output reg tick
); 

  //supported baud rates:
  //idx | baude | tick rate 
  //0   |2400   | 38400
  //1   |4800   | 76800
  //2   |9600   | 153600
  //3   |19200  | 307200
  
  localparam B_2400 = 2'd0;
  localparam B_2400_BR = CLOCK_SPEED/16'd38400;  
  localparam B_4800 = 2'd1; 
  localparam B_4800_BR = CLOCK_SPEED/(17'd76800);  
  localparam B_9600 = 2'd2; 
  localparam B_9600_BR = CLOCK_SPEED/(18'd153600); 
  localparam B_19200 = 2'd3; 
  localparam B_19200_BR = CLOCK_SPEED/(19'd307200); 

  localparam TICK_COUNT_WIDTH = $clog2(MAX_TICK_RATE); 
  reg [TICK_COUNT_WIDTH-1:0]  tick_rate; 
  
  always@(*)
  begin 
    case(baud_rate_idx)
      B_2400:tick_rate = B_2400_BR; 
      B_4800:tick_rate = B_4800_BR; 
      B_9600:tick_rate = B_9600_BR; 
      B_19200:tick_rate = B_19200_BR; 
    endcase 
  end 


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
      if(tick_count == tick_rate-1)
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
