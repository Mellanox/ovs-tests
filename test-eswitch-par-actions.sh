#!/bin/bash
#
# Test parallel change mode and netdev ndo open
# Kernel crash when changing mode to switchdev and configuring bond without waiting.
# [MLNX OFED] Bug SW #1970482: [VF-LAG] Port stuck after configuring pfc and ecn
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# #2860553 - [ASAP, OFED 5.5, korg 5.14, cx6dx] error message appears mlx5_core 0000:08:00.0 enp8s0f0: failed to kill vid 0081/0
if [ `uname -r` == "5.14.0_mlnx" ]; then
    add_expected_error_msg "mlx5_core 0000:08:00.0 enp8s0f0: failed to kill vid 0081/0"
fi

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
        ifconfig $NIC up 2>/dev/null || break
        ifconfig $NIC2 up 2>/dev/null
        ifconfig $NIC down 2>/dev/null
        ifconfig $NIC2 down 2>/dev/null
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
wait # wait for change mode to complete
cleanup

test_done
