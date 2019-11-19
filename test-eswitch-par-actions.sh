#!/bin/bash
#
# Test parallel change mode and netdev ndo open
# Kernel crash when changing mode to switchdev and configuring bond without waiting.
# [MLNX OFED] Bug SW #1970482: [VF-LAG] Port stuck after configuring pfc and ecn
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 0
    config_sriov 0 $NIC2
    config_sriov 2
    config_sriov 2 $NIC2
    unbind_vfs
    unbind_vfs $NIC2
}

function custom_switch_mode() {
    local mode=$1
    local nic=${2:-$NIC}
    local pci=$(basename `readlink /sys/class/net/$nic/device`)
    devlink dev eswitch set pci/$pci mode $mode
}

function test_devlink() {
    echo "set mode switchdev"
    custom_switch_mode switchdev $NIC &
    custom_switch_mode switchdev $NIC2 &
}

function toggle_ports() {
    echo "toggle nic down/up"
    for i in `seq 10`; do
        ifconfig $NIC up || break
        ifconfig $NIC2 up
        ifconfig $NIC down
        ifconfig $NIC2 down
    done
}

function cleanup() {
    config_sriov 0 $NIC2
}


title "Test with devlink"
cleanup
config
test_devlink
toggle_ports
cleanup

test_done
