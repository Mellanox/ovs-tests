#!/bin/bash
#
# Test parallel change mode and netdev ndo open
# with mlnx ofed devlink compat
# Kernel crash when changing mode to switchdev and configuring bond without waiting.
# [MLNX OFED] Bug SW #1970482: [VF-LAG] Port stuck after configuring pfc and ecn
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

if [ "$devlink_compat" != 1 ]; then
    fail "Skipping MLNX OFED with devlink compat test."
fi

function config() {
    config_sriov 0
    config_sriov 0 $NIC2
    config_sriov 2
    config_sriov 2 $NIC2
    unbind_vfs
    unbind_vfs $NIC2
}

function test_mlnx_ofed_devlink_compat() {
    # today devlink compat is async but run echo in background in case it will change
    # to keep the async affect.
    echo switchdev > `devlink_compat_dir $NIC`/mode &
    echo switchdev > `devlink_compat_dir $NIC2`/mode &
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


title "Test with mlnx ofed devlink compat"
cleanup
config
test_mlnx_ofed_devlink_compat
toggle_ports
sleep 10 # wait for change mode to complete
cleanup

test_done
