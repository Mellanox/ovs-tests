#!/bin/bash
#
# Reported by Tonghao Zhang <xiangxia.m.yue@gmail.com>
# [PATCH 1/2] net/mlx5: Avoid panic when setting vport mac, getting vport config
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_legacy
bind_vfs
mac1=`cat /sys/class/net/$VF/address`
# expecting not to crash
ip link set dev $VF vf 0 mac $mac1 2>/dev/null
enable_switchdev
test_done
