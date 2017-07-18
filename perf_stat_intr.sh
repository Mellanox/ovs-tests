#!/bin/bash

# perf stat -e cycles:k,instructions:k -B  --cpu=0-1,6-23 sleep 2
perf stat -e cycles:k,instructions:k -B  --all sleep 2
