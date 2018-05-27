#!/bin/bash
#
# Bug SW #1244622: ECMP - no loadbalance till first failover/failback
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
require_multipath_support


function disable_sriov() {
    echo "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    echo "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function set_switchdev() {
    enable_switchdev $NIC
    enable_switchdev $NIC2
}

function test_lag_affinity() {
    title "Test lag affinity"

    disable_sriov
    ifconfig $NIC down
    ifconfig $NIC2 down

    echo "- Enable multipath"
    enable_sriov
    unbind_vfs $NIC
    unbind_vfs $NIC2
    disable_multipath
    enable_multipath || err "Failed to enable multipath"
    ifconfig $NIC up
    ifconfig $NIC2 up
    set_switchdev

    sec=`get_test_time_elapsed`
    line=`journalctl --since="$sec seconds ago" | grep "lag map port" | tail -1 || true`
    expect="lag map port 1:1 port 2:2"
    echo $line

    if echo $line | grep -q "$expect" ; then
        success
    else
        err "Expected $expect"
    fi

    # cleanup
    echo "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}


test_lag_affinity
test_done
