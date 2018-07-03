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

function _prep() {
    disable_sriov
    ifconfig $NIC up
    ifconfig $NIC2 up
    _st=`date +"%s"`

    echo "- Enable multipath"
    enable_sriov
    unbind_vfs $NIC
    unbind_vfs $NIC2
    disable_multipath
    enable_multipath || err "Failed to enable multipath"
    set_switchdev
}

function _test() {
    local now=`date +"%s"`
    local sec=`echo $now - $_st + 1 | bc`
    local out=`journalctl --since="$sec seconds ago" | grep "lag map port" | tail -1 || true`
    local expect="lag map port 1:1 port 2:2"

    title "-- verify lag affinity"
    echo $out
    if echo $out | grep -q "$expect" ; then
        success
    else
        err "Expected $expect"
    fi
}

function test_lag_affinity() {
    title "Test lag affinity"

    _prep

    # fire netdev events
    ifconfig $NIC down && ifconfig $NIC up
    ifconfig $NIC2 down && ifconfig $NIC2 up
    sleep 1

    _test

    echo "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}

function test_lag_affinity_after_reload() {
    title "Test lag affinity after reload"

    reload_modules
    _prep

    # Do not bring up interfaces. we test initial status.

    _test

    echo "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}


test_lag_affinity
test_lag_affinity_after_reload
test_done
