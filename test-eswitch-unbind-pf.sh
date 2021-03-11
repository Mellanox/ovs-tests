#!/bin/bash
#
# Test unbind pf in switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function run() {
    title "Test unbind PF in switchdev mode"
    config_sriov 2 $NIC
    enable_switchdev
    echo "unbind pf"
    echo $PCI > /sys/bus/pci/drivers/mlx5_core/unbind
    reload_modules
}


run
check_kasan
test_done
