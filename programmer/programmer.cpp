#include "programmer.h"

Programmer::Programmer(const std::string& uart_dev, const std::string& c_program):uart_dev{uart_dev}, c_program{c_program}, uart_fd{-1}
{}; 

Programmer::~Programmer(){
  program_file.close(); 
  close(uart_fd); 
}

void Programmer::setup(){
  uart_fd = open(uart_dev.c_str(),O_RDWR|O_NOCTTY|O_NDELAY);
  if(uart_fd < 0){
    throw std::runtime_error("[x] could not open uart device file"); 
  }

  program_file.open(c_program); 
  if(!program_file.is_open()){
    throw std::runtime_error("[x] could not open object file"); 
  }
 
  //configure serial device
  //verify if device is a tty
  if(!isatty(uart_fd)){
    throw std::runtime_error("[x] uart file is not a tty"); 
  }

  //get old settings 
  if(tcgetattr(uart_fd, &termios_cfg)<0){
    throw std::runtime_error("[x] cannot get current config"); 
  }

  //define settings 
  termios_cfg.c_iflag &= ~(IGNBRK | BRKINT | ICRNL |
                    INLCR | PARMRK | INPCK | ISTRIP | IXON);
  termios_cfg.c_oflag &= ~(OCRNL | ONLCR | ONLRET |
                     ONOCR | OFILL | OLCUC | OPOST);
  termios_cfg.c_lflag &= ~(ECHO | ECHONL | ICANON | IEXTEN | ISIG);
  termios_cfg.c_cflag &= ~(CSIZE | PARENB);
  termios_cfg.c_cflag |= (CS8| CLOCAL|CREAD);
  termios_cfg.c_cc[VMIN] = 1; 
  termios_cfg.c_cc[VTIME]= 0; 
  if(cfsetispeed(&termios_cfg,baud) < 0 || cfsetospeed(&termios_cfg,baud)){
    throw std::runtime_error("[x] could not set termios speed"); 
  }
  
  //apply settings
  if(tcsetattr(uart_fd,TCSAFLUSH,&termios_cfg) < 0){
    throw std::runtime_error("[x] could not apply termios settings"); 
  }

}; 


void Programmer::compile_files(){
  char command[512]; 
  sprintf(command,
      "riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -O2 -Wall -Wextra -T '%s' -I '%s' '%s' '%s' '%s' -o '%s' -lgcc",
      LINK_SCRIPT,LIB_DIR, CRT0, c_program.c_str(), STRING_C,elf_file); 
  std::cout<<"[o] Compiling c program \n"; 
  if(std::system(command)!= 0){
    throw std::runtime_error("could not compile program"); 
  }

  sprintf(command,"riscv64-unknown-elf-objcopy -O binary --only-section=.text '%s' '%s'",elf_file, text_bin);
  std::cout<<"[o] separating text binaries \n"; 
  if(std::system(command) != 0){
    throw std::runtime_error("could not separate text file");  
  }

  sprintf(command,"riscv64-unknown-elf-objcopy -O binary --only-section=.rodata --only-section=.data '%s' '%s'",elf_file,data_bin); 
  if(std::system(command) != 0){
    throw std::runtime_error("could not separate data file"); 
  }
  std::cout << "[o] files compiled and separated"; 
}

int Programmer::send_record(uint8_t* record_buff, uint8_t record_n, uint8_t rcrd_size, uint32_t start_addr, uint8_t dest_mem){
  uint8_t start_addr_0 = 0xFF & (start_addr >> 0); 
  uint8_t start_addr_1 = 0xFF & (start_addr >> 8); 
  uint8_t start_addr_2 = 0xFF & (start_addr >> 16); 
  uint8_t start_addr_3 = 0xFF & (start_addr >> 24); 

  uint8_t header[7] = {rcrd_size, n_recs, dest_mem, start_addr_0, start_addr_1, start_addr_2, start_addr_3}; 

  size_t ret_val =  write(uart_fd,header,7);
  return ret_val; 
}


