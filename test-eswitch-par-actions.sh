#!/bin/bash
#
# Test parallel change mode and config qos and do bond
# Kernel crash when changing mode to switchdev and configuring bond without waiting.
# [MLNX OFED] Bug SW #1970482: [VF-LAG] Port stuck after configuring pfc and ecn
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

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

function config_qos() {
    mlnx_qos -i $NIC2 --trust dscp
    mlnx_qos -i $NIC2 --pfc 0,0,0,1,0,0,0,0
    mlnx_qos -i $NIC --trust dscp
    mlnx_qos -i $NIC --pfc 0,0,0,1,0,0,0,0
}

function action() {
    echo "toggle nic down/up"
    for i in `seq 100`; do
        ifconfig $NIC up
        ifconfig $NIC2 up
        ifconfig $NIC down
        ifconfig $NIC2 down
    done

    echo "qos"
    config_qos &>/dev/null

    echo "bond"
    __ignore_errors=1
    config_bonding $NIC $NIC2
    __ignore_errors=0
}

function cleanup() {
    clear_bonding
    config_sriov 0
    config_sriov 0 $NIC2
    config_sriov 2
}


title "Test with devlink"
cleanup
config
test_devlink
action
cleanup

test_done
