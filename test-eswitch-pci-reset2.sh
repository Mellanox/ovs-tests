#!/bin/bash
#
# Test PCI reset while in switchdev mode and move back to switchdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov
enable_switchdev
echo 1 > /sys/bus/pci/devices/$PCI/reset
sleep 10 # wait for the reset
enable_switchdev
check_kasan
test_done
