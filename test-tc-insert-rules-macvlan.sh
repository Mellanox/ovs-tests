#!/bin/bash
#
# Test rules on macvlan interface
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function test_macvlan() {
    title "Test macvlan"

    tc_test_verbose

    ip link add mymacvlan1 link $NIC type macvlan mode bridge
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


enable_switchdev
test_macvlan
check_kasan
test_done
