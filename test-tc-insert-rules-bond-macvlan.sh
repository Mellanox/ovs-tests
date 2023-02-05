#!/bin/bash
#
# Test rules on macvlan interface over bond
# Feature Request #3102442: Offloading support for Macvlan (passthru mode) over VF LAG bonding device
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    require_interfaces NIC NIC2 REP REP2
    unbind_vfs
    config_bonding $NIC $NIC2
    fail_if_err
    bind_vfs
}

function cleanup() {
    unbind_vfs
    sleep 1
    clear_bonding
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}
trap cleanup EXIT

function test_macvlan() {
    title "Test macvlan over bond"
    tc_test_verbose

    ip link add mymacvlan1 link bond0 type macvlan mode passthru
    reset_tc $REP mymacvlan1

    title "Add rule from mymacvlan1 to $REP"
    tc_filter add dev mymacvlan1 ingress prio 1 protocol ip flower $verbose action mirred egress redirect dev $REP
    verify_in_hw mymacvlan1 1

    title "Add rule from $REP to mymacvlan1"
    tc_filter add dev $REP ingress prio 1 protocol ip flower $verbose action mirred egress redirect dev mymacvlan1
    verify_in_hw $REP 1

    title "Add drop rule on mymacvlan1"
    tc_filter add dev mymacvlan1 ingress prio 2 protocol ip flower $verbose action drop
    verify_in_hw mymacvlan1 2

    reset_tc $REP mymacvlan1
    ip link del dev mymacvlan1
}

config
test_macvlan
cleanup
trap - EXIT
test_done
