module io_apb_bridge
#(
  parameter 
  DATA_WIDTH = 32, 
  N_C = 4 
)
(
  //lsu port
  input clk, reset, 
  input io_write_read,
  input io_req, 
  input [DATA_WIDTH-1:0] io_data_in, 
  input [1:0] io_size, 
  input [DATA_WIDTH-1:0] io_addr_in, 
  output reg io_ack, 
  output reg io_slv_err, 
  output reg [DATA_WIDTH-1:0] io_data_out, 

  //peripheral port
  output reg [N_C-1:0] PSEL,
  output reg PWRITE, 
  output reg PENABLE, 
  output reg [DATA_WIDTH-1:0] PWDATA, 
  output reg [DATA_WIDTH-1:0] PADDR,
  output reg [3:0] PSTRB,
  input [N_C-1:0] PREADY, 
  input [N_C-1:0] PSLVERR, 
  input [(N_C*DATA_WIDTH)-1:0] PRDATA
);
 
  reg PREADY_C;
  reg PSLVERR_C; 
  reg [DATA_WIDTH-1:0] PRDATA_C; 
  integer m; 
  always@(*)
  begin 
    PRDATA_C = 0;
    PREADY_C = 1'b0; 
    PSLVERR_C = 1'b0; 
    for(m = 0; m < N_C; m = m+1)
    begin 
      if(PSEL[m])
      begin 
        PREADY_C = PREADY[m]; 
        PSLVERR_C = PSLVERR[m]; 
        PRDATA_C = PRDATA[(m*DATA_WIDTH) +: DATA_WIDTH]; 
      end
    end
  end
 
  
  ///////////////////////////
  //DECODER PLAN 
  //////////////////////////

  //0xF000_0000 ─ 0xF000_0FFF    Peripheral 0
  //0xF000_1000 ─ 0xF000_1FFF    Peripheral 1
  //0xF000_2000 ─ 0xF000_2FFF    Peripheral 2
  //0xF000_3000 ─ 0xF000_3FFF    Peripheral 3

  reg [N_C-1:0] decoded_sel; 
  wire decode_err; 
 
  integer d;
  always@(*)
  begin
    for(d = 0; d < N_C ; d = d+1)
    begin 
      decoded_sel[d] = (io_addr_in[15:12] == d[3:0]); 
    end 
  end

  assign decode_err = ~|decoded_sel || (|io_addr_in[27:16] != 0);
  
  //BE_logic extracts a load from the bottom lanes, so the data side of this
  //bridge is little endian on both directions: the store is shifted up into the
  //addressed lane, the load is shifted back down. a word access is always
  //aligned, so its shift is 0
  wire [4:0] lane_shift; 
  assign lane_shift = {io_addr_in[1:0], 3'b000}; 

  //the cache zero extends a sub-word read before BE_logic ever sees it, so the
  //io path has to hand back the same shape. a slave that drives all four lanes
  //would otherwise leak the rest of the word into an LBU
  reg [1:0] size_r; 
  wire [DATA_WIDTH-1:0] rd_lane, rd_data; 
  assign rd_lane = PRDATA_C >> {PADDR[1:0], 3'b000}; 
  assign rd_data = (size_r == 2'b00)? {{(DATA_WIDTH-8){1'b0}},  rd_lane[7:0]} : 
                   (size_r == 2'b01)? {{(DATA_WIDTH-16){1'b0}}, rd_lane[15:0]} : rd_lane; 

  wire [3:0] req_strb; 
  assign req_strb = (io_size == 2'b00)? (4'b0001 << io_addr_in[1:0]) : 
                    (io_size == 2'b01)? (4'b0011 << io_addr_in[1:0]) : 4'b1111; 

  localparam IDLE = 2'd0;  
  localparam SETUP = 2'd1; 
  localparam ACCESS = 2'd2; 
  reg [1:0] current_state;  
  always@(posedge clk, posedge reset)
  begin 
    if(reset)
    begin 
      current_state <= IDLE; 
      PSEL <= 0; 
      PWRITE <= 0; 
      PWDATA <= 0; 
      PADDR <= 0; 
      PSTRB <= 0; 
      size_r <= 0; 
      PENABLE <= 0; 
      io_ack <= 0;
      io_data_out <= 0; 
      io_slv_err <= 0; 
    end
    else 
    begin 
      case(current_state)
        IDLE:
        begin 
          if(io_req)
          begin
            if(decode_err)
            begin 
              io_ack <= 1; 
              io_data_out <= 0; 
              io_slv_err <= 1; 
            end 
            else
            begin 
              PSEL <= decoded_sel; 
              PWRITE <= io_write_read; 
              PWDATA <= io_data_in << lane_shift;
              PADDR <= io_addr_in; 
              PSTRB <= req_strb; 
              size_r <= io_size; 
              current_state <= SETUP; 
              io_ack <= 0; 
              io_slv_err <= 0; 
            end
          end
          else 
          begin 
            PENABLE <= 0;
            PSEL <= 0; 
            io_ack <= 0; 
            io_slv_err <= 0;
          end 
        end
        SETUP: 
        begin 
          PENABLE <= 1; 
          current_state <= ACCESS; 
        end 
        ACCESS:
        begin 
          if(PREADY_C)
          begin 
            PENABLE <= 0; 
            PSEL <= 0; 
            io_ack <= 1; 
            io_data_out <= rd_data; 
            io_slv_err <= PSLVERR_C; 
            current_state <= IDLE; 
          end 
        end
        default: 
          current_state <= IDLE; 
      endcase
    end
  end
endmodule 

