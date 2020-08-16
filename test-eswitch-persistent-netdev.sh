#!/bin/bash
#
# This test is checking the new uplink rep mode where uplink rep is not a new netdev device.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function get_ifindex() {
    local nic=$1
    cat /sys/class/net/$nic/ifindex
}

function verify_ifindex() {
    local tmp1=`get_ifindex $NIC` || err "Failed to get ifindex for $NIC"
    local tmp2=`get_ifindex $NIC2` || err "Failed to get ifindex for $NIC2"
    if [ "$nicid" != "$tmp1" ]; then
        err "Nic $NIC changed ifindex"
    fi
    if [ "$nicid2" != "$tmp2" ]; then
        err "Nic $NIC2 changed ifindex"
    fi
}

function test_ifindex() {
    title "disable sriov"
    config_sriov 0
    config_sriov 0 $NIC2
    sleep 0.5
    nicid=`get_ifindex $NIC` || fail "Failed to get ifindex for $NIC"
    nicid2=`get_ifindex $NIC2` || fail "Failed to get ifindex for $NIC2"
    title "enable sriov"
    config_sriov 2
    config_sriov 2 $NIC2
    sleep 0.5
    verify_ifindex
    title "enable switchdev"
    enable_switchdev
    enable_switchdev $NIC2
    sleep 0.5
    verify_ifindex
    title "cleanup"
    config_sriov 0
    config_sriov 0 $NIC2
}

test_ifindex
test_done
