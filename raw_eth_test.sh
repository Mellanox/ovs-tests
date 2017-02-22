#!/bin/sh

export MLX5_WQE_MIN_INLINE_SIZE=40
export MLX5_DEBUG_MASK=4
export MLX5_DEBUG=1
export LD_LIBRARY_PATH=/usr/local/lib/libmlx5

raw_ethernet_bw --client -B e4:11:22:11:4a:50 -E e4:11:22:11:4a:51 -K 9999 -k 9999 -J 1.1.1.6 -j 1.1.1.5 --tcp
