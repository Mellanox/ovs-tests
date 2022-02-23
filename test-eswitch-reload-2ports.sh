#!/bin/bash
#
# Test reload mlx5 modules while both ports in switchdev
#
# Bug SW #2681985: [ASAP, OFED5.4] call trace and memory leak appeared after stop driver in switchdev mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev
config_sriov 2 $NIC2
enable_switchdev $NIC2
reload_modules
config_sriov 0 $NIC2
config_sriov
enable_switchdev

test_done
