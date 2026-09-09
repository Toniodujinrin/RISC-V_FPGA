#ifndef PROGRAMMER_H 
#define PROGRAMMER_H 

#include <iostream> 
#include <termios.h> 
#include <unistd.h>
#include <fcntl.h>
#include <string>
#include <fstream> 
#include <filesystem>
#include <stdio.h>



class Programmer{
  public: 
  Programmer(const std::string& uart_dev,
      const std::string& c_program); 
  ~Programmer(); 
  Programmer(const Programmer&) = delete; 
  Programmer& operator=(const Programmer&)=delete; 
  void setup(); 
  int start_transmition(); 
  void compile_files(); 

  private: 
  termios termios_cfg; 
  const speed_t baud = B115200; //Processor boatloader only accepts this baud rate 
  const char* LINK_SCRIPT = "./link.ld"; 
  const char* LIB_DIR = "./lib"; 
  const char* CRT0 = "./crt0.s"; 
  const char* STRING_C = "./string.c"; 
  const char* elf_file = "./elf_file.elf";
  const char* text_bin = "./text_bin.bin";
  const char* data_bin = "./data_bin.bin";

  

  std::string uart_dev; 
  std::string c_program;
  int uart_fd; 
  void rx(char* buffer);
  void tx(std::string msg); 
  void create_records(); 
  int send_record(uint8_t* record_buff, uint8_t record_n, uint8_t rcrd_size, uint32_t start_addr, uint8_t dest_mem); 

  uint8_t n_recs; 
}; 


#endif 
