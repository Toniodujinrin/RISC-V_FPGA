//ladder step 2: one program across all three RAM sections. values is const so
//it lands in .rodata, base is an initialised global so it lands in .data, and
//total is uninitialised so it lands in .bss and crt0 has to clear it.
//
//volatile on values is load bearing: without it gcc folds the whole sum at -O2
//and never reads memory at all, leaving the data image proving nothing
volatile const int values[8] = {3, 1, 4, 1, 5, 9, 2, 6};
int base = 7;
int total;

int main(void)
{
  for(int i = 0; i < 8; i++)
    total += values[i];
  total += base;
  //31 from .rodata plus 7 from .data, starting from a .bss that crt0 zeroed
  return total == 38? 0 : total;
}
