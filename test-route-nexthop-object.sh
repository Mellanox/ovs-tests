#!/bin/bash
#
# Test adding route with nexthop object
#
# Bug SW #2891499
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


LOCAL_TUN=7.7.7.7
LOCAL_TUN_ROUTE=7.7.7.0/24

config_sriov 2
config_sriov 0 $NIC2
enable_switchdev

function cleanup() {
    ip a flush dev $NIC
    ip nexthop del id 1 &>/dev/null
    ip route del $LOCAL_TUN_ROUTE &>/dev/null
    sleep 0.5
}

cleanup

# Add route with nexthop object
ip address add $LOCAL_TUN/24 dev $NIC
ip link set dev $NIC up
ip nexthop add id 1 dev $NIC
ip route del $LOCAL_TUN_ROUTE
ip route add $LOCAL_TUN_ROUTE nhid 1

cleanup
test_done
