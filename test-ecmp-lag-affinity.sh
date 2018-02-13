#!/bin/bash
#
# Bug SW #1244622: ECMP - no loadbalance till first failover/failback
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_multipath_support


function disable_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    title "- Enable SRIOV"
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
    disable_multipath
    ifconfig $NIC down
    ifconfig $NIC2 down

    title "- Enable multipath"
    enable_multipath || err "Failed to enable multipath"
    enable_sriov
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
    disable_sriov
    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}


test_lag_affinity
test_done
