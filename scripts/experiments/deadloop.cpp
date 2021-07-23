#include <signal.h>
#include <iostream>

sig_atomic_t stop = 0;

void handle(int param){
        stop = 1;
}

int main(){
        signal(SIGINT, handle);

        while(!stop){

        }

        std::cout << "stopping" << std::endl;
        return 0;
}
