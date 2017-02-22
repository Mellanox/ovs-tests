#!/bin/sh

# traffic vm5->vm6
./noodle -c 1.1.1.6 -b 1 -l 2000 -p 9999 -C 10000 -n 50

./noodle -c 1.1.1.6 -b 50 -l 2000 -p 9999 -C 6000 -n 1000  
