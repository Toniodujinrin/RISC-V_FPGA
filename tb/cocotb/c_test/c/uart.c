#include <stddef.h>
#include <stdint.h>


#define UART_TX_D_REG_ADDR  0xF0001000 
#define UART_RX_D_REG_ADDR  0xF0001001 
#define UART_CTRL_REG_ADDR  0xF0001002 
#define UART_CFG_REG_ADDR   0xF0001003
#define UART_STAT_REG_ADDR  0xF0001004 

//STATUS bit positions, per rtl/io/uart.v
#define UART_STAT_TX_BUSY   (1u << 0)
#define UART_STAT_RX_BUSY   (1u << 1)
#define UART_STAT_TX_EMPTY  (1u << 2)
#define UART_STAT_RX_VALID  (1u << 3)
#define UART_STAT_PARITY_ERR (1u << 4)

//RX_OVERRUN is set by hardware but lives in CONTROL, not STATUS: STATUS is read
//only, so the bit has to sit somewhere software can write it back down
#define UART_CTRL_RX_OR     (1u << 4)

typedef struct{
  uint8_t UART_PARITY_TYPE; 
  uint8_t UART_BAUD_IDX; 
  uint8_t UART_DATA_BITS;
  uint8_t UART_STOP_BITS; 
  uint8_t UART_PARITY_EN; 
  uint8_t UART_EN; 
  uint8_t UART_RX_EN;
  uint8_t UART_TX_EN;
  uint8_t UART_RX_OR; 
  volatile uint8_t* CFG_REG; 
  volatile uint8_t* CTRL_REG; 
  volatile uint8_t* RX_DATA_REG; 
  volatile uint8_t* TX_DATA_REG; 
  volatile uint8_t* STAT_REG; 
} UART_HandleTypeDef; 



void uart_configure(UART_HandleTypeDef* tuart ); 

int uart_transmit(UART_HandleTypeDef*tuart,uint8_t* buff, uint8_t size, uint32_t cycle_wait); 

int uart_receive(UART_HandleTypeDef* tuart, uint8_t* buffer, uint8_t size, uint32_t cycle_wait); 

int main(){
  UART_HandleTypeDef tuart;
  tuart.UART_TX_EN = 1; 
  tuart.UART_PARITY_EN = 0; 
  tuart.UART_BAUD_IDX = 2; 
  tuart.UART_STOP_BITS = 1;
  tuart.UART_PARITY_TYPE = 0; 
  tuart.UART_DATA_BITS = 7; 
  tuart.UART_RX_EN = 1; 
  tuart.UART_RX_OR = 0; 
  tuart.UART_EN = 1; 

  uint8_t buff[] = "hello world"; 
  uart_configure(&tuart); 

  //sizeof counts the terminator the string literal brought with it, and the
  //terminator is not part of the message
  //
  //a bit is 16 ticks and a tick is hundreds of clocks, so the polls below spin
  //for thousands of iterations per byte. the timeout has to clear that by a
  //wide margin or a healthy transmitter reads as a dead one
  int ret_val = uart_transmit(&tuart, buff, sizeof(buff) - 1, 100000); 

  return ret_val; 
}


void uart_configure(UART_HandleTypeDef* tuart ){
  
  uint8_t UART_CFG = tuart->UART_BAUD_IDX|(tuart->UART_DATA_BITS << 2)|(tuart->UART_STOP_BITS << 5)|(tuart->UART_PARITY_TYPE << 7); 
  uint8_t UART_CTRL = tuart->UART_PARITY_EN|(tuart->UART_EN << 1)|(tuart->UART_RX_EN << 2)|(tuart->UART_TX_EN << 3)| (tuart->UART_RX_OR << 4); 
  tuart->TX_DATA_REG = (uint8_t*) UART_TX_D_REG_ADDR; 
  tuart->RX_DATA_REG = (uint8_t*) UART_RX_D_REG_ADDR; 
  tuart->CTRL_REG = (uint8_t*) UART_CTRL_REG_ADDR; 
  tuart->STAT_REG = (uint8_t*) UART_STAT_REG_ADDR; 
  tuart->CFG_REG = (uint8_t*) UART_CFG_REG_ADDR;

  *(tuart->CFG_REG) = UART_CFG;
  *(tuart->CTRL_REG) = UART_CTRL; 
}



int uart_transmit(UART_HandleTypeDef*tuart,uint8_t* buff, uint8_t size, uint32_t cycle_wait){
  uint8_t pointer = 0; 
  uint32_t counter; 
  
  while(pointer < size){
    counter = 0; 
    while(!(*(tuart->STAT_REG) & UART_STAT_TX_EMPTY) && counter < cycle_wait)
      counter++; 
    
    //the loop also ends on the timeout, so ask again rather than assume
    if(!(*(tuart->STAT_REG) & UART_STAT_TX_EMPTY))
       return -1; 

    //transmit 
    *(tuart->TX_DATA_REG) = buff[pointer]; 
    pointer++; 
  }

  counter = 0; 
  while(!(*(tuart->STAT_REG) & UART_STAT_TX_EMPTY) && counter < cycle_wait)
    counter++; 

  return (*(tuart->STAT_REG) & UART_STAT_TX_EMPTY)? 0 : -1; 
}


int uart_receive(UART_HandleTypeDef* tuart, uint8_t* buffer, uint8_t size, uint32_t cycle_wait){
  uint8_t pointer = 0; 
  uint32_t counter; 

  while (pointer < size){
   
    //check if overrun bit if set, if so deassert, so receiving can start 
    if(*(tuart->CTRL_REG) & UART_CTRL_RX_OR){
      *(tuart->CTRL_REG) &= ~UART_CTRL_RX_OR;
    }

    counter = 0; 
    while(!(*(tuart->STAT_REG) & UART_STAT_RX_VALID) && counter < cycle_wait)
      counter++; 

    if(!(*(tuart->STAT_REG) & UART_STAT_RX_VALID))
      return -1; 

    //the read is what consumes the byte and drops RX_VALID
    buffer[pointer] = *(tuart->RX_DATA_REG); 
    pointer++; 
  }
  return 0; 
}
