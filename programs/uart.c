#include <stddef.h>
#include <stdint.h>
#include <string.h>


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

//RX_OVERRUN is set by hardware but lives in CONTROL
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

static int send_string(UART_HandleTypeDef *tuart, const char *str)
{
    return uart_transmit(
        tuart,
        (uint8_t *)str,
        (uint8_t)strlen(str),
        100000
    );
}


static int receive_line(
    UART_HandleTypeDef *tuart,
    uint8_t *buffer,
    uint8_t max_size
)
{
    uint8_t index = 0;
    uint8_t c;

    //Read characters individually until ENTER is pressed.
    while(index < max_size - 1) {
        if(uart_receive(tuart, &c, 1, 1000000) != 0)
            continue;
        if(c == '\r' || c == '\n') {

            if(index == 0)
                continue;
            break;
        }

        buffer[index++] = c;

        //Echo the typed character so the terminal behaves
        uart_transmit(tuart, &c, 1, 100000);
    }
    buffer[index] = '\0';
    send_string(tuart, "\r\n");
    return index;
}


//deterministic pseudo-random number generator.

static uint32_t next_random(uint32_t *state)
{
    *state = (*state * 17u) + 23u;
    *state ^= (*state >> 3);
    *state += 41u;
    return *state;
}


int main()
{
    UART_HandleTypeDef tuart;

    tuart.UART_TX_EN       = 1;
    tuart.UART_PARITY_EN   = 0;
    tuart.UART_BAUD_IDX    = 2;
    tuart.UART_STOP_BITS   = 1;
    tuart.UART_PARITY_TYPE = 0;
    tuart.UART_DATA_BITS   = 7;
    tuart.UART_RX_EN       = 1;
    tuart.UART_RX_OR       = 0;
    tuart.UART_EN          = 1;

    uint8_t input_buff[32];

    /*
     * Seed doesn't need to be genuinely random for this demo.
     */
    uint32_t rng_state = 0x12345678u;

    uint32_t player_score = 0;
    uint32_t cpu_score    = 0;

    uart_configure(&tuart);

    send_string(
        &tuart,
        "\r\n"
        "====================================\r\n"
        "Rock Paper Scissors over UART!\r\n"
        "====================================\r\n"
        "\r\n"
        "Commands:\r\n"
        "  rock\r\n"
        "  paper\r\n"
        "  scissors\r\n"
        "  info\r\n"
        "  stop\r\n"
        "\r\n"
    );
    while(1) {

        send_string(&tuart, "RV32I> ");
        int received = receive_line(
            &tuart,
            input_buff,
            sizeof(input_buff)
        );
        if(received <= 0)
            continue;
        /*
         * Exit command
         */
        if(strcmp((char *)input_buff, "stop") == 0) {

            send_string(
                &tuart,
                "CPU: Shutting down game.\r\n"
                "Thanks for playing!\r\n"
            );

            break;
        }


        if(strcmp((char *)input_buff, "info") == 0) {
            send_string(
                &tuart,
                "\r\n"
                "CPU INFORMATION\r\n"
                "---------------\r\n"
                "ISA: RV32I\r\n"
                "Pipeline: 5-stage\r\n"
                "Branch Predictor: G-share\r\n"
                "L1 Cache: Enabled\r\n"
                "UART: MMIO RX/TX\r\n"
                "Software: Bare-metal C\r\n"
                "\r\n"
            );
            continue;
        }


        uint8_t player_choice;

        if(strcmp((char *)input_buff, "rock") == 0) {
            player_choice = 0;
        }
        else if(strcmp((char *)input_buff, "paper") == 0) {
            player_choice = 1;
        }
        else if(strcmp((char *)input_buff, "scissors") == 0) {
            player_choice = 2;
        }
        else {

            send_string(
                &tuart,
                "CPU: Unknown command. "
                "Enter rock, paper, scissors, info, or stop.\r\n"
            );

            continue;
        }


        /*
         * Generate CPU move:
         *
         * 0 = rock
         * 1 = paper
         * 2 = scissors
         */
        uint8_t cpu_choice =
            (uint8_t)(next_random(&rng_state) % 3u);


        send_string(&tuart, "CPU chose: ");

        if(cpu_choice == 0)
            send_string(&tuart, "rock\r\n");

        else if(cpu_choice == 1)
            send_string(&tuart, "paper\r\n");

        else
            send_string(&tuart, "scissors\r\n");

        //Determine winner.
        if(player_choice == cpu_choice) {

            send_string(
                &tuart,
                "CPU: Draw. Rematch!\r\n\r\n"
            );
        }

        else if(
            (player_choice == 0 && cpu_choice == 2) ||
            (player_choice == 1 && cpu_choice == 0) ||
            (player_choice == 2 && cpu_choice == 1)
        ) {

            player_score++;

            send_string(
                &tuart,
                "CPU: You win this round!\r\n\r\n"
            );
        }

        else {

            cpu_score++;

            send_string(
                &tuart,
                "CPU: I win this round :)\r\n\r\n"
            );
        }


        /*
         * Mix some runtime-dependent state into the PRNG.
         * This still isn't real randomness, but user choices
         * will influence future CPU moves.
         */
        rng_state +=
            player_score * 11u +
            cpu_score * 7u +
            player_choice * 13u;
    }
    return 0;
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
