#!/bin/bash
#
# Test unbind pf in switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function run() {
    title "Test unbind PF in switchdev mode"
    config_sriov
    enable_switchdev
    log "unbind pf"
    echo $PCI > /sys/bus/pci/drivers/mlx5_core/unbind
    log "bind pf"
    echo $PCI > /sys/bus/pci/drivers/mlx5_core/bind
    config_sriov
}


run
check_kasan
test_done
