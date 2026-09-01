//ladder step 1: a loop and nothing else. no globals and no calls, so this runs
//on registers and branches alone -- it passes before .data or the stack work
int main(void)
{
  int a = 0, b = 1;
  for(int i = 0; i < 10; i++)
  {
    int next = a + b;
    a = b;
    b = next;
  }

  return a == 55? 0 : a;
}
