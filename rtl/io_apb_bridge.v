module apb_interconnect
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
  input [(N_C*DATA_WIDTH)-1:0] PRDATA
);
 
  reg PREADY_C;
  reg [DATA_WIDTH-1:0] PRDATA_C; 
  integer i; 
  always@(*)
  begin 
    PRDATA_C = 0;
    PREADY_C = 1'b0; 
    for(i = 0; i < N_C; i = i+1)
    begin 
      if(PSEL[i])
      begin 
        PREADY_C = PREADY[i]; 
        PRDATA_C = PRDATA[(i*DATA_WIDTH) +: DATA_WIDTH]; 
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

  wire [3:0] decoded_sel; 
  wire decode_err; 

  assign decoded_sel[0] = (io_addr_in[15:12] == 4'h0); 
  assign decoded_sel[1] = (io_addr_in[15:12] == 4'h1); 
  assign decoded_sel[2] = (io_addr_in[15:12] == 4'h2); 
  assign decoded_sel[3] = (io_addr_in[15:12] == 4'h3); 
  
  assign decode_err = ~|decoded_sel;
  
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
              PWDATA <= io_data_in ;
              PADDR <= io_addr_in; 
              PSTRB <= 4'b1111; 
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
            io_data_out <= PRDATA_C; 
            current_state <= IDLE; 
          end 
        end
      endcase
    end
  end
endmodule 

