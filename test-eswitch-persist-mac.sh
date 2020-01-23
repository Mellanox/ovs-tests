#!/bin/bash
#
# Test mac not reset to zero when moving from legacy to switchdev
#
# Bug SW #2064431: [Upstream] Switching mode to switchdev is cleaning vfs mac
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function test_mac() {
    title "Test mac reset"

    start_check_syndrome

    enable_legacy
    title "- set mac on vf 0"
    ip link set $NIC vf 0 mac e4:05:01:04:00:02 || fail "Failed to set mac on vf 0"
    ip link show dev $NIC
    enable_switchdev

    title "- test mac not zero"
    mac=`ip -j link show dev $NIC | jq '.[0].vfinfo_list[0].address'`
    if [ "$mac" == "00:00:00:00:00:00" ]; then
        err "Expected vf 0 mac not to be zero"
    else
        ip link show dev $NIC
        success
    fi

    check_syndrome
}


config_sriov 2
test_mac
test_done
