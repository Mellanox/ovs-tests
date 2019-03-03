#!/bin/bash
#
# Reported by Tonghao Zhang <xiangxia.m.yue@gmail.com>
# [PATCH net 2/2] net/mlx5: Avoid panic when setting VF rate
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
bind_vfs
# expecting not to crash
ip link set dev $VF vf 0 min_tx_rate 1 max_tx_rate 2 2>/dev/null
ip link set dev $VF vf 0 min_tx_rate -1 max_tx_rate -1 2>/dev/null
test_done
