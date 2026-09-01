module data_mem //simulate byte addressed memory
#(
  parameter 
  DATA_WIDTH = 32, 
  BLOCK_BITS = 256, //32 bytes or 8 words 
  D_MEM_DEPTH = 1024, 
  WORD_OFF_BITS = 3, 
  //.data and .rodata land here. the core has no data path to instruction
  //memory, so crt0 cannot copy them out of the program image the way it would
  //on a von Neumann machine -- they have to be loaded straight into this array
  DATA_FILE = "build/data.mem"
)
(
  input clk, reset, 
  output reg mem_ready, 
  output reg data_out_valid, 
  output reg [BLOCK_BITS-1:0] data_out, 
  input [DATA_WIDTH-1:0] addr_in, 
  input addr_in_valid, 
  input [BLOCK_BITS-1:0] data_in, 
  input data_in_valid, 
  input write_read
); 
  localparam N_WORDS    = 1 << WORD_OFF_BITS;
  localparam ADDR_WIDTH = $clog2(D_MEM_DEPTH);

  localparam IDLE    = 2'd0;
  localparam READING = 2'd1;
  localparam WRITING = 2'd2;
  reg [1:0] current_state;

  reg [WORD_OFF_BITS-1:0] word_counter;
  //latch inputs 
  reg [DATA_WIDTH-1:0]  addr_r;
  reg [BLOCK_BITS-1:0]  block_r;

  wire accept = addr_in_valid && (!write_read || data_in_valid);

  //addr_r is a byte address, mem is a word array, so the low two bits go. the
  //WORD_OFF_BITS of the word index rather than being added to it, so a request
  //cpu address is truncated in to match actual memory address bits

  wire [ADDR_WIDTH-1:0] mem_index =
       {addr_r[ADDR_WIDTH+1 : 2+WORD_OFF_BITS], word_counter};

  reg [DATA_WIDTH-1:0] mem [0:D_MEM_DEPTH-1];

  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      current_state  <= IDLE;
      word_counter   <= 0;
      mem_ready      <= 1;
      data_out_valid <= 0;
      data_out       <= 0;
      addr_r         <= 0;
      block_r        <= 0;
    end
    else
    begin
      data_out_valid <= 0;
      case(current_state)
        IDLE:
        begin
          word_counter <= 0;
          if(accept)
          begin
            addr_r        <= addr_in;
            block_r       <= data_in;   //only meaningful for a write
            mem_ready     <= 0;         //busy until the burst completes 
            current_state <= write_read ? WRITING : READING;
          end
        end

        READING:
        begin
          data_out[(word_counter*DATA_WIDTH) +: DATA_WIDTH] <= mem[mem_index];
          if(word_counter == N_WORDS-1)
          begin
            word_counter   <= 0;
            data_out_valid <= 1;
            mem_ready      <= 1;
            current_state  <= IDLE;
          end
          else
            word_counter <= word_counter + 1;
        end

        WRITING:
        begin
          mem[mem_index] <= block_r[(word_counter*DATA_WIDTH) +: DATA_WIDTH];
          if(word_counter == N_WORDS-1)
          begin 
            word_counter  <= 0;
            mem_ready     <= 1;
            current_state <= IDLE;
          end
          else
            word_counter <= word_counter + 1;
        end
        default:
          current_state <= IDLE;
      endcase
    end
  end


  integer i; 
  initial 
  begin 
    for(i = 0; i < D_MEM_DEPTH; i = i+1)
    begin 
      mem[i] = {DATA_WIDTH{1'b0}}; 
    end
    //zeroed first, so an image shorter than the array leaves .bss ready to go
    $readmemb(DATA_FILE, mem); 
  end

endmodule
