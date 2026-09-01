
volatile int int_arr[] = {1,3,4,5,6,7,8}; 

int main(){

  int r = 4; 
  int c = 5; 
  int g = r*c; 
  int f = (int) r/c; 
  
  int res = 0; 
  for(int i = 0; i < sizeof(int_arr)/sizeof(int); i++){
    if(i%2 == 0){
      res += int_arr[i]; 
    }
  } 

  return res == 19? 0: res; 
}
