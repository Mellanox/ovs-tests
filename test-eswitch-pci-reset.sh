#!/bin/bash
#
# Test PCI reset while in switchdev mode and reload modules
#
# Bug SW #2805586: [Upstream] null-ptr-deref in mlx5e_suspend+0x9c/0x130 while reseting PCI in switchdev mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov
enable_switchdev
echo 1 > /sys/bus/pci/devices/$PCI/reset
sleep 10 # wait for the reset
reload_modules
config_sriov
test_done
