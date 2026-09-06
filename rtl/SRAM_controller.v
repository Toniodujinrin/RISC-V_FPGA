module SRAM_controller
#(
  parameter 
  DATA_WIDTH = 32, 
  BLOCK_BITS = 256, 
  MEM_DATA_WIDTH = 16, 
  MEM_ADDR_WIDTH = 13, 
  MEM_COL_ADDR_WIDTH = 10,
  BURST_LEN = 16,//using full page bursts   
  T_CLK = 20
)
(
  input clk, reset,

  
  //mem port 
  output reg [MEM_ADDR_WIDTH-1:0] mem_addr_in, 
  output reg [MEM_DATA_WIDTH-1:0] mem_data_in, 
  //DQ is one bidirectional bus. this module never drives it directly -- it
  //raises mem_data_oe and the top level builds the pad:
  //  assign DQ = mem_data_oe ? mem_data_in : {MEM_DATA_WIDTH{1'bz}};
  //  always @(*) mem_data_out = DQ;
  //keeping the tri-state at the pad rather than in here is what lets the
  //module stay synthesisable stand-alone and simulate against a DQ model.
  output reg mem_data_oe, 
  output reg [1:0] mem_bank_select, 
  output mem_clk_en, 
  output mem_l_byte_en, 
  output mem_u_byte_en, 
  output reg mem_we_n,
  output reg mem_cas_n,
  output reg mem_ras_n, 
  output reg mem_cs_n,
  input [MEM_DATA_WIDTH-1:0] mem_data_out, 
  
  //cpu port 
  output reg mem_ready, 
  output reg data_out_valid,
  output [BLOCK_BITS-1:0] data_out,  
  input [BLOCK_BITS-1:0] cpu_data_in, 
  input [DATA_WIDTH-1:0] cpu_addr_in, 
  input cpu_in_valid,
  input cpu_write_read
);

  //tie these signals
  assign mem_clk_en = 1'b1; 
  assign mem_u_byte_en = 1'b0; 
  assign mem_l_byte_en = 1'b0; 

  reg mem_we_n_next; 
  reg mem_cas_n_next; 
  reg mem_ras_n_next;
  reg mem_cs_n_next; 
  reg [1:0] mem_bank_select_next;
  reg [MEM_ADDR_WIDTH-1:0] mem_addr_in_next;
  reg [MEM_DATA_WIDTH-1:0] mem_data_in_next;
  reg mem_data_oe_next; 
  reg mem_ready_next;
  reg [BLOCK_BITS-1:0] cpu_data_in_reg, cpu_data_in_next; 
  reg cpu_wr_reg, cpu_wr_next; 
  reg [5:0] cpu_u_c_addr_reg, cpu_u_c_addr_next; 

  reg [$clog2(BURST_LEN+1)-1:0] burst_counter, burst_counter_next; 
  reg [BLOCK_BITS-1:0] read_buffer, read_buffer_next; 
  reg data_out_valid_next; 
  
  assign data_out = read_buffer; 
  
  //ADDRESS MAPPING 
  wire [MEM_ADDR_WIDTH-1:0] cpu_r_addr = cpu_addr_in[23:11]; 
  wire [1:0] cpu_b_addr = cpu_addr_in[25:24]; 
  wire [5:0] cpu_u_c_addr = cpu_addr_in[10:5]; 



  //DEVICE STATES: 
  //INITIALIZATION STATES
  localparam INIT_IDLE = 4'd0;
  localparam PRECHARGE_ALL = 4'd1;  
  localparam AUTO_REFRESH_1 = 4'd2; 
  localparam AUTO_REFRESH_2 = 4'd3; 
  localparam SET_MODE = 4'd4; 
  localparam NORMAL_IDLE = 4'd5; 
  localparam ACTIVATE = 4'd6; 
  localparam READ_BURST = 4'd7; 
  localparam WRITE_BURST = 4'd8;
  localparam PRECHARGE = 4'd9; 
  localparam PERIODIC_REFRESH = 4'd10;  

  reg [3:0] current_state, next_state; 
  
  //DEVICE TIMING 
  localparam Pwait = (100000+T_CLK-1)/T_CLK; 
  localparam tRP  = (20+T_CLK-1)/T_CLK; 
  localparam tRC  = (60+T_CLK-1)/T_CLK; 
  localparam tMRD = 2; 
  localparam tRCD = (15+T_CLK-1)/T_CLK; 
  localparam tCAS = 2;
  localparam REFRESH_PERIOD = 64000000/(8192*T_CLK); 
  reg [$clog2(Pwait)-1:0] counter, counter_next;

  reg [$clog2(REFRESH_PERIOD):0] refresh_counter;  
  reg refresh_done, refresh_done_next; 
  reg refresh_pending;

  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      current_state <= INIT_IDLE; 
      counter <= 0; 
      mem_ras_n <= 1; 
      mem_cas_n <= 1; 
      mem_we_n <= 1; 
      mem_cs_n <= 1; 
      mem_bank_select <= 0;
      mem_addr_in <= 0; 
      mem_data_in <= 0;
      mem_data_oe <= 0; 
      mem_ready <= 0; 
      cpu_data_in_reg <= 0; 
      cpu_wr_reg <= 0; 
      cpu_u_c_addr_reg <= 0; 
      burst_counter <= 0; 
      read_buffer <= 0; 
      data_out_valid <= 0;
      refresh_counter <= 0;
      refresh_done <= 0; 
      refresh_pending <= 0; 
    end 
    else 
    begin 
      counter <= counter_next; 
      current_state <= next_state; 
      mem_ras_n <= mem_ras_n_next; 
      mem_cas_n <= mem_cas_n_next; 
      mem_we_n <= mem_we_n_next; 
      mem_cs_n <= mem_cs_n_next; 
      mem_bank_select <= mem_bank_select_next;
      mem_addr_in <= mem_addr_in_next; 
      mem_data_in <= mem_data_in_next; 
      mem_data_oe <= mem_data_oe_next; 
      mem_ready <= mem_ready_next;
      cpu_data_in_reg <= cpu_data_in_next;
      cpu_wr_reg <= cpu_wr_next; 
      cpu_u_c_addr_reg <= cpu_u_c_addr_next;
      burst_counter <= burst_counter_next; 
      read_buffer <= read_buffer_next;
      data_out_valid <= data_out_valid_next; 
      refresh_done <= refresh_done_next; 
      if(refresh_counter >= REFRESH_PERIOD-1)
        refresh_counter <= 0; 
      else 
        refresh_counter <= refresh_counter + 1'b1; 

      if(refresh_counter >= REFRESH_PERIOD-1)
        refresh_pending <= 1'b1; 
      else if(refresh_done)
        refresh_pending <= 1'b0; 
    end 
  end 

  always@(*)
  begin 
    next_state = current_state; 
    mem_addr_in_next = mem_addr_in; 
    mem_data_in_next = mem_data_in; 
    mem_data_oe_next = 1'b0; 
    mem_bank_select_next = mem_bank_select; 
    mem_ras_n_next = mem_ras_n; 
    mem_cas_n_next = mem_cas_n; 
    mem_we_n_next = mem_we_n; 
    mem_cs_n_next = mem_cs_n; 
    counter_next = counter;
    mem_ready_next = mem_ready; 
    cpu_data_in_next = cpu_data_in_reg;
    cpu_wr_next = cpu_wr_reg; 
    cpu_u_c_addr_next = cpu_u_c_addr_reg; 
    burst_counter_next = burst_counter; 
    read_buffer_next = read_buffer;
    data_out_valid_next = 0; 
    refresh_done_next = 0; 
    case(current_state) 
      INIT_IDLE: 
      begin 
        if(counter == Pwait)
        begin 
          counter_next = 0; //reset counter for next
          next_state = PRECHARGE_ALL; 
          mem_addr_in_next[10] = 1;
          //command (PALL)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 0; 
        end 
        else 
        begin
          counter_next = counter + 1;
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
        end 
      end 
      PRECHARGE_ALL: 
      begin 
        if(counter == tRP)
        begin 
          counter_next = 0;
          next_state = AUTO_REFRESH_1; 
          //command (REF)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 1; 
        end
        else //set NOP 
        begin 
          counter_next = counter + 1; 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
        end 
      end 
      AUTO_REFRESH_1: 
      begin
        if(counter == tRC)
        begin 
          counter_next = 0; 
          next_state = AUTO_REFRESH_2; 
          //command(REF)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 1; 
        end
        else //set NOP 
        begin 
          counter_next = counter + 1; 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
        end 
      end 
      AUTO_REFRESH_2: 
      begin
        if(counter == tRC)
        begin 
          counter_next = 0; 
          next_state = SET_MODE; 
          //command(MRS)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 0; 
          //set config, sequential full page 
          mem_addr_in_next = 13'b0;
          mem_addr_in_next[9:0] = 10'b0000100111;  
        end
        else //set NOP 
        begin
          counter_next = counter + 1; 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
        end 
      end 
      SET_MODE: 
      begin 
        if(counter == tMRD)
        begin 
          counter_next = 0; 
          next_state = NORMAL_IDLE;
          mem_ready_next = 1; 
        end 
        else //set NOP 
        begin
          counter_next = counter + 1; 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
        end 
      end
      NORMAL_IDLE:
      begin 
        if(cpu_in_valid && mem_ready)
        begin
          //command(ACT)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
          mem_bank_select_next = cpu_b_addr; 
          mem_addr_in_next = cpu_r_addr; 
          cpu_u_c_addr_next = cpu_u_c_addr;
          cpu_data_in_next = cpu_data_in; 
          cpu_wr_next = cpu_write_read; 
          mem_ready_next = 0;
          next_state = ACTIVATE;
          counter_next = 0; 
        end
        else if(refresh_pending && !refresh_done)
        begin 
          //command(REF). legal here because all banks are idle: every
          //transaction ends in PRECHARGE and init ends in PALL.
          mem_cs_n_next = 0; 
          mem_ras_n_next = 0; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 1; 
          mem_ready_next = 0; 
          counter_next = 0; 
          next_state = PERIODIC_REFRESH; 
        end 
        else  //NOP 
        begin 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 1; 
          mem_we_n_next = 1;
          mem_ready_next = !refresh_pending; 
        end 
      end 
      ACTIVATE: 
      begin
       if(counter == tRCD)
       begin 
         if(cpu_wr_reg)//write 
         begin 
          //command (WRITE)
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 0; 
          mem_addr_in_next = 0; 
          mem_addr_in_next[9:4] = cpu_u_c_addr_reg;
          mem_addr_in_next[3:0] = 4'b0000;
          mem_addr_in_next[10]  = 1'b0; // no auto-precharge
          //first data comes in with the commans 
          mem_data_in_next = cpu_data_in_reg[(burst_counter_next*MEM_DATA_WIDTH) +: MEM_DATA_WIDTH]; 
          mem_data_oe_next = 1'b1; 
          burst_counter_next = burst_counter + 1; 
          next_state = WRITE_BURST; 
         end
         else //read, no precharge 
         begin 
          mem_cs_n_next = 0; 
          mem_ras_n_next = 1; 
          mem_cas_n_next = 0; 
          mem_we_n_next = 1; 
          mem_addr_in_next = 0;
          mem_addr_in_next[9:4] = cpu_u_c_addr_reg;
          mem_addr_in_next[3:0] = 4'b0000;
          mem_addr_in_next[10]  = 1'b0; // no auto-precharge
          next_state = READ_BURST;
          burst_counter_next = 0;
         end 
         counter_next = 0; 
       end
       else //NOP 
       begin 
         counter_next = counter + 1; 
         mem_cs_n_next = 0; 
         mem_ras_n_next = 1; 
         mem_cas_n_next = 1; 
         mem_we_n_next = 1;
       end 
      end
      READ_BURST: 
      begin
        if(counter == tCAS) 
        begin 
           read_buffer_next[(burst_counter*MEM_DATA_WIDTH)+: MEM_DATA_WIDTH] = mem_data_out; 
           burst_counter_next = burst_counter+1; 
           if(burst_counter == BURST_LEN-2)//terminate page burst 
           begin 
             mem_cs_n_next = 1'b0; 
             mem_ras_n_next = 1'b1; 
             mem_cas_n_next = 1'b1; 
             mem_we_n_next = 1'b0; 
           end 
           else //NOP
           begin 
              mem_cs_n_next = 1'b0; 
              mem_ras_n_next = 1'b1; 
              mem_cas_n_next = 1'b1; 
              mem_we_n_next = 1'b1;
           end 
           if(burst_counter == BURST_LEN-1)
           begin 
              counter_next = 0; 
              data_out_valid_next = 1'b1; 
              next_state = PRECHARGE; 
              burst_counter_next = 0;
           end 
        end 
        else
        begin 
          counter_next = counter + 1; 
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b1; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b1;
        end 
      end
      WRITE_BURST:
      begin 
        if(burst_counter == BURST_LEN)
        begin 
          //command(BST). the device ignores data applied coincident with BST,
          //so the last word had to go out on the previous cycle.
           mem_cs_n_next = 1'b0; 
           mem_ras_n_next = 1'b1; 
           mem_cas_n_next = 1'b1; 
           mem_we_n_next = 1'b0; 
          //go to Precharge 
          burst_counter_next = 0; 
          counter_next = 0; 
          next_state = PRECHARGE; 
        end
        else //NOP
        begin 
          mem_data_in_next = cpu_data_in_reg[(burst_counter*MEM_DATA_WIDTH) +: MEM_DATA_WIDTH]; 
          mem_data_oe_next = 1'b1; 
          burst_counter_next = burst_counter + 1; 
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b1; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b1;
        end 
      end
      PRECHARGE: 
      begin
        if(counter == 0)
        begin 
          //command(PRE). the bank is still selected from the ACT and A10 is 0
          //from the column address, so this precharges that bank only.
          counter_next = counter + 1; 
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b0; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b0; 
        end 
        else if(counter == tRP)
        begin 
          counter_next = 0;
          next_state = NORMAL_IDLE; 
          mem_ready_next = !refresh_pending; 
          //NOP, otherwise the defaults hold PRE on the bus another cycle
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b1; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b1;
        end 
        else //NOP 
        begin 
          counter_next = counter + 1; 
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b1; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b1;
        end 
      end
      PERIODIC_REFRESH: 
      begin 
        if(counter == tRC)
        begin 
          counter_next = 0; 
          next_state = NORMAL_IDLE;
          refresh_done_next = 1; 
        end
        else
        begin 
          counter_next = counter + 1; 
          mem_cs_n_next = 1'b0; 
          mem_ras_n_next = 1'b1; 
          mem_cas_n_next = 1'b1; 
          mem_we_n_next = 1'b1;
        end
      end 
      default: next_state = current_state; 
    endcase 
  end
endmodule
