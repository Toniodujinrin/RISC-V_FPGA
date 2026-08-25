module cache_controller
#(
  parameter ADDR_BITS = 32,
  parameter DATA_WIDTH = 32,
  parameter BLOCK_BITS = 32*8,
  parameter WORD_OFF_BITS = 3,  
  parameter WB_FIFO_DEPTH = 64
)
(
  input clk, reset,
  //cpu port
  input cpu_data_in_valid,
  input cpu_write_read,
  input [DATA_WIDTH-1:0] cpu_data_in,
  input [1:0] cpu_size, //00 byte, 01 half, 10/11 word
  input [ADDR_BITS-1:0] cpu_addr_in,
  output reg [DATA_WIDTH-1:0] cpu_data_out,
  output reg cpu_ready_out,
  output reg cpu_data_out_valid,

  //memory port
  input mem_ready,
  input mem_data_in_valid,
  input [BLOCK_BITS-1:0] mem_data_in,
  output reg mem_write_read,
  output reg [ADDR_BITS-1:0] mem_addr_in,
  output reg mem_addr_in_valid,
  output reg [BLOCK_BITS-1:0] mem_data_out,
  output reg mem_data_out_valid
);

  //cache wires
  reg cpu_cache_write_read;
  reg cpu_cache_valid;
  reg [ADDR_BITS-1:0] cpu_cache_addr_in;
  reg [DATA_WIDTH-1:0] cpu_cache_data_in;
  reg [1:0] cpu_cache_size;
  reg mem_cache_missed_valid_in;
  reg [BLOCK_BITS-1:0] mem_cache_missed_block_in;
  wire [DATA_WIDTH-1:0] cpu_cache_data_out;
  wire cpu_cache_valid_out;
  wire cpu_cache_ready;
  wire [BLOCK_BITS-1:0] fifo_cache_evicted_block;
  wire [ADDR_BITS-1:0] fifo_cache_evicted_addr;
  wire fifo_cache_evicted_valid;
  wire mem_cache_miss_valid;
  wire [ADDR_BITS-1:0] mem_cache_miss_addr;
  reg [ADDR_BITS-1:0] mem_cache_miss_addr_r;
  reg mem_cache_miss_pending;

  //fifo wires
  reg [BLOCK_BITS-1:0] cache_fifo_data_in;
  reg [ADDR_BITS-1:0] cache_fifo_addr_in;
  reg cache_fifo_write_en;
  reg mem_fifo_read_en;
  wire [BLOCK_BITS-1:0] mem_fifo_data_out;
  wire [ADDR_BITS-1:0] mem_fifo_addr_out;
  wire mem_fifo_output_valid;
  wire fifo_full;
  wire fifo_empty;

  //write back staging. the cache pulses evicted_valid for a single cycle and
  //does not wait for the fifo, so the victim is held here until the fifo can
  //take it. only one eviction can ever be outstanding: the cache stalls in its
  //*_MISS state until missed_valid_in, and the miss is not allowed onto the
  //memory port until the write back has been queued.
  reg [BLOCK_BITS-1:0] evict_hold_block;
  reg [ADDR_BITS-1:0] evict_hold_addr;
  reg evict_hold_valid;
  reg drain_mode;

  //arbiter wires
  wire [1:0] arbiter_grant;
  wire fifo_grant = arbiter_grant[1];
  wire cache_grant = arbiter_grant[0];

  //a miss may only take the memory port once its write back is safely queued,
  //and a full fifo forces a complete drain before the miss resumes
  wire cache_req = mem_cache_miss_pending && !evict_hold_valid && !drain_mode;
  wire fifo_req  = !fifo_empty;

  write_back_buffer
  #(
    .BLOCK_BITS(BLOCK_BITS),
    .ADDR_BITS(ADDR_BITS),
    .DEPTH(WB_FIFO_DEPTH)
  )
  WRITE_BACK
  (
    .clk(clk),
    .reset(reset),
    .data_in(cache_fifo_data_in),
    .addr_in(cache_fifo_addr_in),
    .write_en(cache_fifo_write_en),
    .read_en(mem_fifo_read_en),
    .data_out(mem_fifo_data_out),
    .addr_out(mem_fifo_addr_out),
    .output_valid(mem_fifo_output_valid),
    .full(fifo_full),
    .empty(fifo_empty)
  );

  cache
  #(
    .ADDR_BITS(ADDR_BITS),
    .WORD_OFF_BITS(WORD_OFF_BITS),
    .BYTE_OFF_BITS(2),
    .BLOCK_BITS(BLOCK_BITS),
    .SET_BITS(7),
    .DATA_WIDTH(DATA_WIDTH),
    .WAY_N(4)
  )
  CACHE
  (
    .clk(clk),
    .reset(reset),
    .write_read(cpu_cache_write_read),
    .valid(cpu_cache_valid),
    .addr(cpu_cache_addr_in),
    .data_in(cpu_cache_data_in),
    .size(cpu_cache_size),
    .missed_valid_in(mem_cache_missed_valid_in),
    .missed_block_in(mem_cache_missed_block_in),
    .data_out(cpu_cache_data_out),
    .output_valid(cpu_cache_valid_out),
    .ready(cpu_cache_ready),
    .evicted_block(fifo_cache_evicted_block),
    .evicted_address(fifo_cache_evicted_addr),
    .evicted_valid(fifo_cache_evicted_valid),
    .miss_valid(mem_cache_miss_valid),
    .miss_addr(mem_cache_miss_addr)
  );

  memory_arbiter
  ARBITER
  (
    .req({fifo_req, cache_req}),
    .grant(arbiter_grant)
  );


  // cpu port control
  localparam C_PORT_IDLE = 1'b0;
  localparam C_PORT_REQ  = 1'b1;
  reg c_current_state;
  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      c_current_state <= C_PORT_IDLE;
      cpu_ready_out <= 1;
      cpu_cache_write_read <= 0;
      cpu_cache_valid <= 0;
      cpu_cache_data_in <= 0;
      cpu_cache_size <= 0;
      cpu_cache_addr_in <= 0;
      cpu_data_out <= 0;
      cpu_data_out_valid <= 0;
    end
    else
    begin
      cpu_cache_valid <= 0; //single cycle request into the cache
      case(c_current_state)
      C_PORT_IDLE:
      begin
        if(cpu_data_in_valid & cpu_cache_ready)
        begin
          cpu_cache_write_read <= cpu_write_read;
          cpu_cache_valid <= 1;
          cpu_ready_out <= 0;
          cpu_cache_data_in <= cpu_data_in;
          cpu_cache_size <= cpu_size;
          cpu_cache_addr_in <= cpu_addr_in;
          cpu_data_out_valid <= 0;
          c_current_state <= C_PORT_REQ;
        end
        else
        begin
          cpu_ready_out <= 1;
          cpu_data_out_valid <= 0;
        end
      end
      C_PORT_REQ:
      begin
        //the cache pulses output_valid for loads and stores alike
        if(cpu_cache_valid_out)
        begin
          cpu_data_out <= cpu_cache_data_out;
          cpu_data_out_valid <= 1;
          cpu_ready_out <= 1;
          c_current_state <= C_PORT_IDLE;
        end
      end
      endcase
    end
  end


  //write back path: capture the eviction, then push it into the fifo as soon as
  //there is room for it
  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      evict_hold_block <= 0;
      evict_hold_addr <= 0;
      evict_hold_valid <= 0;
      cache_fifo_data_in <= 0;
      cache_fifo_addr_in <= 0;
      cache_fifo_write_en <= 0;
      drain_mode <= 0;
    end
    else
    begin
      cache_fifo_write_en <= 0;

      if(fifo_cache_evicted_valid)
      begin
        evict_hold_block <= fifo_cache_evicted_block;
        evict_hold_addr  <= fifo_cache_evicted_addr;
        evict_hold_valid <= 1;
      end
      else if(evict_hold_valid && !fifo_full)
      begin
        cache_fifo_data_in  <= evict_hold_block;
        cache_fifo_addr_in  <= evict_hold_addr;
        cache_fifo_write_en <= 1;
        evict_hold_valid    <= 0;
      end

      //an eviction that arrives at a full fifo halts the miss until the fifo has
      //been emptied out completely
      if(drain_mode)
      begin
        if(fifo_empty)
          drain_mode <= 0;
      end
      else if(fifo_cache_evicted_valid && fifo_full)
        drain_mode <= 1;
    end
  end


  //mem port control
  localparam M_PORT_IDLE      = 3'd0;
  localparam M_PORT_FIFO_READ = 3'd1;
  localparam M_PORT_WRITE_REQ = 3'd2;
  localparam M_PORT_READ_REQ  = 3'd3;
  localparam M_PORT_READ_WAIT = 3'd4;
  reg [2:0] m_current_state;
  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      m_current_state <= M_PORT_IDLE;
      mem_write_read <= 0;
      mem_addr_in <= 0;
      mem_addr_in_valid <= 0;
      mem_data_out <= 0;
      mem_data_out_valid <= 0;
      mem_fifo_read_en <= 0;
      mem_cache_missed_valid_in <= 0;
      mem_cache_missed_block_in <= 0;
      mem_cache_miss_addr_r <= 0;
      mem_cache_miss_pending <= 0;
    end
    else
    begin
      mem_fifo_read_en <= 0;
      mem_cache_missed_valid_in <= 0;

      //miss_valid is a single cycle pulse, so the address is registered here and
      //held until the memory port can actually serve it
      if(mem_cache_miss_valid)
      begin
        mem_cache_miss_addr_r <= mem_cache_miss_addr;
        mem_cache_miss_pending <= 1;
      end

      case(m_current_state)
      M_PORT_IDLE:
      begin
        if(fifo_grant)
        begin
          mem_fifo_read_en <= 1;
          m_current_state <= M_PORT_FIFO_READ;
        end
        else if(cache_grant)
        begin
          mem_write_read <= 0;
          mem_addr_in <= mem_cache_miss_addr_r;
          mem_addr_in_valid <= 1;
          m_current_state <= M_PORT_READ_REQ;
        end
      end

      M_PORT_FIFO_READ: //fifo read data lands one cycle after read_en
      begin
        if(mem_fifo_output_valid)
        begin
          mem_write_read <= 1;
          mem_addr_in <= mem_fifo_addr_out;
          mem_addr_in_valid <= 1;
          mem_data_out <= mem_fifo_data_out;
          mem_data_out_valid <= 1;
          m_current_state <= M_PORT_WRITE_REQ;
        end
      end

      M_PORT_WRITE_REQ:
      begin
        if(mem_addr_in_valid && mem_ready)
        begin
          mem_addr_in_valid <= 0;
          mem_data_out_valid <= 0;
          m_current_state <= M_PORT_IDLE;
        end
      end

      M_PORT_READ_REQ:
      begin
        if(mem_addr_in_valid && mem_ready)
        begin
          mem_addr_in_valid <= 0;
          m_current_state <= M_PORT_READ_WAIT;
        end
      end

      M_PORT_READ_WAIT:
      begin
        if(mem_data_in_valid)
        begin
          mem_cache_missed_block_in <= mem_data_in;
          mem_cache_missed_valid_in <= 1;
          mem_cache_miss_pending <= 0;
          m_current_state <= M_PORT_IDLE;
        end
      end

      default: m_current_state <= M_PORT_IDLE;
      endcase
    end
  end
endmodule

module write_back_buffer
#(
  parameter 
  BLOCK_BITS = 64*8, 
  ADDR_BITS = 32, 
  DEPTH = 64
)
(
  input clk,reset, 
  input [BLOCK_BITS-1:0] data_in, 
  input [ADDR_BITS-1:0] addr_in, 
  input write_en, 
  input read_en,
  output reg [BLOCK_BITS-1:0] data_out, 
  output reg  [ADDR_BITS-1:0] addr_out, 
  output reg output_valid, 
  output full, 
  output empty
); 
  
  localparam PTR_BITS = $clog2(DEPTH)+1;
  reg [PTR_BITS-1:0] write_ptr; 
  reg [PTR_BITS-1:0] read_ptr; 

  assign full = (write_ptr[PTR_BITS-1] != read_ptr[PTR_BITS-1]) && 
    (write_ptr[PTR_BITS-2:0] == read_ptr[PTR_BITS-2:0]); 
  assign empty = write_ptr == read_ptr; 

  wire write_allowed = write_en && !full; 
  wire read_allowed = read_en && !empty;  

  (* ramstyle = "block" *) reg [(BLOCK_BITS+ADDR_BITS)-1:0] mem [0:DEPTH-1];
  always@(posedge clk)
  begin 
    if(write_allowed)
    begin   
      mem[write_ptr[PTR_BITS-2:0]] <= {addr_in,data_in};
    end
    
    data_out <= mem[read_ptr[PTR_BITS-2:0]][BLOCK_BITS-1:0]; 
    addr_out <= mem[read_ptr[PTR_BITS-2:0]][(BLOCK_BITS+ADDR_BITS)-1:BLOCK_BITS];
  end
  
  //ptr ctrl
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      write_ptr <= 0;
      read_ptr <= 0;
      output_valid <= 0;
    end
    else 
    begin 
      write_ptr <= write_allowed? write_ptr + 1'b1 : write_ptr; 
      read_ptr <= read_allowed ? read_ptr+ 1'b1 : read_ptr;  
      output_valid <= read_allowed? 1'b1 : 1'b0; 
    end
  end
endmodule 



//2 consumer fixed priority arbiter 
module memory_arbiter
(
  input wire [1:0] req,   
  output reg [1:0] grant
);
  always@(*)
  begin 
    grant = 0; 
    if(req[0])
      grant[0] = 1; 
    else if (req[1])
      grant[1] = 1; 
  end
endmodule 



//cache 
module cache
#(
  parameter ADDR_BITS = 32,
  parameter WORD_OFF_BITS = 4,
  parameter BYTE_OFF_BITS = 2,
  parameter BLOCK_OFF_BITS = WORD_OFF_BITS + BYTE_OFF_BITS,
  parameter BLOCK_BITS = 64*8, //64bytes
  parameter SET_BITS = 7,
  parameter TAG_BITS = ADDR_BITS-(BLOCK_OFF_BITS+SET_BITS),
  parameter DATA_WIDTH = 32,
  parameter WAY_N = 4
)
(
  input clk, reset,
  input write_read,
  input valid,
  input [ADDR_BITS-1:0] addr,
  input [DATA_WIDTH-1:0] data_in,
  input [1:0] size, //00 byte, 01 half, 10/11 word
  input missed_valid_in,
  input [BLOCK_BITS-1:0] missed_block_in,
  output reg [DATA_WIDTH-1:0] data_out,
  output reg output_valid,
  output reg ready,
  output reg [BLOCK_BITS-1:0] evicted_block,
  output reg [ADDR_BITS-1:0] evicted_address,
  output reg evicted_valid,
  output reg miss_valid,
  output reg [ADDR_BITS-1:0] miss_addr
);
  localparam SET_N  = 1 << SET_BITS;
  localparam SIZE_B = 2'b00; 
  localparam SIZE_H = 2'b01; 
  localparam WORD_N = 1 << WORD_OFF_BITS;
  localparam BYTE_N = 1 << BYTE_OFF_BITS;
  localparam WAY_SEL_BITS = $clog2(WAY_N);

  localparam IDLE        = 3'd0;
  localparam DELAY_STATE = 3'd1;
  localparam DOING_WRITE = 3'd2;
  localparam DOING_READ  = 3'd3;
  localparam WRITE_MISS  = 3'd4;
  localparam READ_MISS   = 3'd5;
  reg [2:0] current_state;

  reg [(WAY_N*BLOCK_BITS)-1:0] cache_data_in;
  reg [WAY_N-1:0] cache_write_data_en;
  wire [(WAY_N*BLOCK_BITS)-1:0] cache_data_out;
  reg [(WAY_N*BLOCK_BITS)-1:0] cache_data_out_r;
  reg [SET_BITS-1:0] cache_write_data_addr;

  reg [(WAY_N*TAG_BITS)-1:0] cache_tag_in;
  reg [WAY_N-1:0] cache_write_tag_en;
  wire [(WAY_N*TAG_BITS)-1:0] cache_tag_out;
  reg [SET_BITS-1:0] cache_write_tag_addr;

  wire [SET_BITS-1:0]      set_index  = addr[BLOCK_OFF_BITS +: SET_BITS];
  wire [TAG_BITS-1:0]      tag_index  = addr[BLOCK_OFF_BITS+SET_BITS +: TAG_BITS];
  wire [WORD_OFF_BITS-1:0] word_index = addr[BYTE_OFF_BITS +: WORD_OFF_BITS];
  wire [BYTE_OFF_BITS-1:0] byte_index = addr[BYTE_OFF_BITS-1:0];

  reg [SET_BITS-1:0] set_index_r;
  reg [TAG_BITS-1:0] tag_index_r;
  reg write_read_r;
  reg [DATA_WIDTH-1:0] data_in_r;
  reg [WORD_OFF_BITS-1:0] word_index_r;
  reg [BYTE_OFF_BITS-1:0] byte_index_r;
  reg [1:0] size_r;
  reg [ADDR_BITS-1:0] addr_r;

  reg [(DATA_WIDTH)-1:0]        way_word_data_write;
  reg [BLOCK_BITS-1:0]          way_block_data_write;
  reg [(WAY_N*BLOCK_BITS)-1:0]  way_cache_data_write;
  reg [(DATA_WIDTH)-1:0]        way_word_data_read;
  reg [BLOCK_BITS-1:0]          way_block_data_read;
  reg [DATA_WIDTH-1:0]          way_data_out;

  //per-set / per-way state (flat arrays: only the state is per set, the
  //compare and replacement logic below is shared)
  reg [(WAY_N*TAG_BITS)-1:0] set_tag_in_cache;
  //flat so they reset in one assignment: index {set, way}
  reg [(SET_N*WAY_N)-1:0] valid_bits_pw; //per_way valid bits
  reg [(SET_N*WAY_N)-1:0] dirty_bits_pw; //per_way dirty bits
  reg [(SET_N*(WAY_N-1))-1:0] access_rec; //per_set tree plru nodes

  reg [WAY_N-1:0] comparison;
  wire hit = |comparison;
  reg [WAY_SEL_BITS-1:0] selected_way;
  reg [WAY_SEL_BITS-1:0] max_record;
  //the victim is latched in DELAY_STATE so that the access_rec read and the plru
  //decode get a cycle of their own instead of feeding the block mux that drives
  //evicted_block. access_rec for this set cannot change between DELAY_STATE and
  //the access completing -- update_access_rec only runs in the states that end
  //the access -- so the registered copy is what the live decode would give.
  reg [WAY_SEL_BITS-1:0] max_record_r;
  wire [WAY_N-1:0] max_record_r_oh = 1 << max_record_r;
  //access records of the set currently being looked up (parallels set_tag_in_cache)
  wire [WAY_N-2:0] set_access_rec =
       access_rec[set_index_r*(WAY_N-1) +: (WAY_N-1)];

  reg [WAY_N-1:0] set_way_select;      //also serves as write_en, and evicted way select
  reg [WAY_SEL_BITS-1:0] set_way_select_num;
  wire set_hit_miss = hit;
  wire set_output_valid = (current_state == DOING_READ) || (current_state == DOING_WRITE);
  wire set_evict_valid = !hit && valid_bits_pw[{set_index_r, max_record_r}]
                              && dirty_bits_pw[{set_index_r, max_record_r}];

  integer k, n, t;

  //memory is banked "way-wise"
  genvar i;
  generate
    for(i = 0; i < WAY_N; i = i+1 )
    begin:BANKS
      //DATA BANKS
      cache_bram
      #(
        .DATA_WIDTH(BLOCK_BITS),
        .DEPTH(SET_N)
      )
      DATA_BRAMS_WAY_I
      (
        .clk(clk),
        .write_addr(cache_write_data_addr),
        .write_enable(cache_write_data_en[i]),
        .read_addr(set_index),
        .data_in(cache_data_in[i*BLOCK_BITS +: BLOCK_BITS]),
        .data_out(cache_data_out[i*BLOCK_BITS +: BLOCK_BITS])
      );

      //TAG BANKS
      cache_bram
      #(
        .DATA_WIDTH(TAG_BITS),
        .DEPTH(SET_N)
      )
      TAG_BRAMS_WAY_I
      (
        .clk(clk),
        .write_addr(cache_write_tag_addr),
        .write_enable(cache_write_tag_en[i]),
        .read_addr(set_index),
        .data_in(cache_tag_in[i*TAG_BITS +: TAG_BITS]),
        .data_out(cache_tag_out[i*TAG_BITS +: TAG_BITS])
      );
    end
  endgenerate


  //tag compare + priority encode of the matching way
  always@(*)
  begin
    selected_way = 0;
    for(n = 0; n < WAY_N; n = n+1)
    begin
      comparison[n] = (set_tag_in_cache[n*TAG_BITS +: TAG_BITS] == tag_index_r)
                      && valid_bits_pw[{set_index_r, n[WAY_SEL_BITS-1:0]}];
      if(comparison[n])
        selected_way = n[WAY_SEL_BITS-1:0];
    end
  end

  //max record 4 ways selector (least recently used victim)
  always@(*)
  begin
    if(set_access_rec[0])
    begin 
      if(set_access_rec[1])
        max_record = 2'd3; 
      else 
        max_record = 2'd2;
    end
    else 
    begin 
      if(set_access_rec[2])
        max_record = 2'd1; 
      else 
        max_record = 2'd0; 
    end
  end

  //hit -> the matching way, miss -> the victim way
  always@(*)
  begin
    if(hit)
    begin
      set_way_select     = comparison;
      set_way_select_num = selected_way;
    end
    else
    begin
      set_way_select     = max_record_r_oh;
      set_way_select_num = max_record_r;
    end
  end

  task update_access_rec;
    input [SET_BITS-1:0] set_i;
    input [WAY_SEL_BITS-1:0] way_i;
    begin
        if(way_i < 2)
        begin 
          access_rec[set_i*(WAY_N-1) + 0] <= 1'b1;           //lru side is now {2,3}
          access_rec[set_i*(WAY_N-1) + 2] <= (way_i == 0);   //lru within {0,1}
        end 
        else
        begin 
          access_rec[set_i*(WAY_N-1) + 0] <= 1'b0;           //lru side is now {0,1}
          access_rec[set_i*(WAY_N-1) + 1] <= (way_i == 2);   //lru within {2,3}
        end
    end
  endtask

  //inner cache control
  always@(posedge clk, posedge reset)
  begin
    if(reset)
    begin
      ready <= 1;
      set_index_r <= 0;
      tag_index_r <= 0;
      byte_index_r <= 0;
      word_index_r <= 0;
      size_r <= 0;
      write_read_r <= 0;
      addr_r <= 0;
      cache_write_tag_en <= 0;
      cache_write_data_en <= 0;
      cache_write_tag_addr <= 0;
      cache_write_data_addr <= 0;
      cache_data_in <= 0;
      cache_tag_in <= 0;
      cache_data_out_r <= 0;
      set_tag_in_cache <= 0;
      max_record_r <= 0;
      current_state <= IDLE;
      data_in_r <= 0;
      output_valid <= 0;
      data_out  <= 0;
      evicted_block <= 0;
      evicted_address <= 0;
      evicted_valid <= 0;
      miss_valid <= 0;
      miss_addr <= 0;
      valid_bits_pw <= 0;
      dirty_bits_pw <= 0;
      access_rec <= 0;
    end
    else
    begin
      //bram write enables are single cycle pulses
      cache_write_data_en <= 0;
      cache_write_tag_en  <= 0;

      case(current_state)
      IDLE:
      begin
        output_valid  <= 0;
        evicted_valid <= 0;
        miss_valid    <= 0;
        if(valid && ready)
        begin
          ready <= 0;
          set_index_r <= set_index;
          tag_index_r <= tag_index;
          word_index_r <= word_index;
          byte_index_r <= byte_index;
          size_r <= size;
          write_read_r  <= write_read;
          data_in_r <= data_in;
          addr_r <= addr;
          current_state <= DELAY_STATE;
        end
        else
        begin
          //hold off while a bram write is still in flight, the read port
          //would otherwise return pre-write data for the same set
          ready <= !(|cache_write_data_en) && !(|cache_write_tag_en);
        end
      end
      DELAY_STATE: //wait for memory read
      begin
        set_tag_in_cache <= cache_tag_out;
        cache_data_out_r <= cache_data_out;
        max_record_r <= max_record;
        if(write_read_r)
          current_state <= DOING_WRITE;
        else
          current_state <= DOING_READ;
      end
      DOING_WRITE:
      begin
        if(set_output_valid)
        begin
          if(!set_hit_miss) // miss
          begin
            if(set_evict_valid) //evict output to the controller
            begin
              evicted_valid <= 1;
              evicted_block <= cache_data_out_r[set_way_select_num*BLOCK_BITS +: BLOCK_BITS];
              evicted_address <= {
                    set_tag_in_cache[set_way_select_num*TAG_BITS +: TAG_BITS],
                    set_index_r,{BLOCK_OFF_BITS{1'b0}}
                    };
            end
            miss_valid <= 1;
            miss_addr <= {addr_r[ADDR_BITS-1:BLOCK_OFF_BITS], {BLOCK_OFF_BITS{1'b0}}};
            //wait for the block to be fetched
            current_state <= WRITE_MISS;
          end
          else
          begin
            //write data READ-MODIFY-WRITE
            cache_write_data_en   <= set_way_select;
            cache_write_data_addr <= set_index_r;
            cache_data_in         <= way_cache_data_write;
            dirty_bits_pw[{set_index_r, set_way_select_num}] <= 1;
            update_access_rec(set_index_r, set_way_select_num);
            //acknowledge the store
            output_valid  <= 1;
            current_state <= IDLE;
          end
        end
      end

      WRITE_MISS:
      begin
        evicted_valid <= 0;
        miss_valid <= 0;
        if(missed_valid_in)
        begin
            //update tag
            for(k = 0; k < WAY_N; k = k+1)
            begin
              if(set_way_select[k])
                cache_tag_in[k*TAG_BITS +: TAG_BITS] <= tag_index_r;
            end
            cache_write_tag_en   <= set_way_select;
            cache_write_tag_addr <= set_index_r;
            //update fetched block merged with the pending store
            cache_write_data_en   <= set_way_select;
            cache_write_data_addr <= set_index_r;
            cache_data_in         <= way_cache_data_write;
            valid_bits_pw[{set_index_r, set_way_select_num}] <= 1;
            dirty_bits_pw[{set_index_r, set_way_select_num}] <= 1; //store merged in
            update_access_rec(set_index_r, set_way_select_num);
            output_valid  <= 1;
            current_state <= IDLE;
        end
      end
      DOING_READ:
      begin
        if(set_output_valid)
        begin
          if(!set_hit_miss) //miss
          begin
            if(set_evict_valid)
            begin
               evicted_valid <= 1;
               evicted_block <= cache_data_out_r[set_way_select_num*BLOCK_BITS +: BLOCK_BITS];
               evicted_address <= {
                    set_tag_in_cache[set_way_select_num*TAG_BITS +: TAG_BITS],
                    set_index_r,{BLOCK_OFF_BITS{1'b0}}
                    };
            end
            miss_valid <= 1;
            miss_addr <= {addr_r[ADDR_BITS-1:BLOCK_OFF_BITS], {BLOCK_OFF_BITS{1'b0}}};
            current_state <= READ_MISS;
          end
          else
          begin
            data_out <= way_data_out;
            output_valid <= 1;
            update_access_rec(set_index_r, set_way_select_num);
            current_state <= IDLE;
          end
        end
      end

      READ_MISS:
      begin
        miss_valid <= 0;
        evicted_valid <= 0;
        if(missed_valid_in)
        begin
          //update tag and data
          for(k = 0; k < WAY_N; k = k+1)
          begin
            if(set_way_select[k])
            begin
              cache_tag_in[k*TAG_BITS +: TAG_BITS] <= tag_index_r;
              cache_data_in[k*BLOCK_BITS +: BLOCK_BITS] <= missed_block_in;
            end
          end
          cache_write_data_en   <= set_way_select;
          cache_write_data_addr <= set_index_r;
          cache_write_tag_en    <= set_way_select;
          cache_write_tag_addr  <= set_index_r;
          valid_bits_pw[{set_index_r, set_way_select_num}] <= 1;
          dirty_bits_pw[{set_index_r, set_way_select_num}] <= 0;
          update_access_rec(set_index_r, set_way_select_num);

          //set output
          data_out <= way_data_out;
          output_valid <= 1;
          current_state <= IDLE;
        end
      end
      default: current_state <= IDLE;
      endcase
    end
  end

  //read strobe: word_index_r picks the word in the block, byte_index_r the byte in that word
  always@(*)
  begin
    way_block_data_read = (current_state == READ_MISS) ? missed_block_in :
                cache_data_out_r[set_way_select_num*BLOCK_BITS +: BLOCK_BITS];
    way_word_data_read = way_block_data_read[(word_index_r*DATA_WIDTH) +: DATA_WIDTH];
    //sub-word results are zero-extended here; the core sign-extends for LB/LH.
    case(size_r)
      SIZE_B:  way_data_out = { {(DATA_WIDTH-8){1'b0}},  way_word_data_read[byte_index_r*8 +: 8] };
      SIZE_H:  way_data_out = { {(DATA_WIDTH-16){1'b0}}, way_word_data_read[byte_index_r[1]*16 +: 16] };
      default: way_data_out = way_word_data_read;
    endcase
  end

  //write strobe: same word/byte selection, read-modify-write of the addressed byte
  always@(*)
  begin
    way_block_data_write = (current_state == WRITE_MISS) ? missed_block_in :
                cache_data_out_r[set_way_select_num*BLOCK_BITS +: BLOCK_BITS];
    way_word_data_write = way_block_data_write[(word_index_r*DATA_WIDTH) +: DATA_WIDTH];
    //store data is taken from the low bits of data_in_r, which is where SB/SH
    //put it, not from the lane the address selects.
    case(size_r)
      SIZE_B:  way_word_data_write[byte_index_r*8 +: 8]      = data_in_r[7:0];
      SIZE_H:  way_word_data_write[byte_index_r[1]*16 +: 16] = data_in_r[15:0];
      default: way_word_data_write = data_in_r;
    endcase
    way_block_data_write[(word_index_r*DATA_WIDTH) +: DATA_WIDTH] = way_word_data_write;

    way_cache_data_write = cache_data_out_r;
    for (t = 0; t < WAY_N; t = t+1)
    begin
      if(set_way_select[t])
        way_cache_data_write[t*BLOCK_BITS +: BLOCK_BITS] = way_block_data_write;
    end
  end
endmodule


module cache_bram #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 128
)(
    input wire clk,

    // Write Port
    input wire write_enable,
    input wire [$clog2(DEPTH)-1:0] write_addr,
    input wire [DATA_WIDTH-1:0] data_in,

    // Read Port
    input wire [$clog2(DEPTH)-1:0] read_addr,
    output reg [DATA_WIDTH-1:0] data_out
);

    (* ramstyle = "block" *) reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    always @(posedge clk) begin
        if (write_enable) begin
            ram[write_addr] <= data_in;
        end

        data_out <= ram[read_addr];
    end
endmodule
