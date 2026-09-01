

int fact(int a){
  if(a == 0){
    return 1; 
  }
  return a * fact(a-1); 
}

int main(){
  
  int c = fact(5);
  return c == 120?0:c; 
}
