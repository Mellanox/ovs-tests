#!/bin/bash
#
# Test basic matchall rule
#
# require cls_matchall and act_police modules.
#
# Bug SW #1909500: Rate limit is not working in openstack ( tc rule not in hw)

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function test_basic_matchall_rep() {
    title "Test matchall rule on REP $REP"

    reset_tc $REP
    tc_filter add dev $REP root prio 1 protocol ip matchall skip_sw action police rate 1mbit burst 20k
    reset_tc $REP
}

function test_basic_matchall_uplink_rep() {
    title "Test matchall rule on uplink rep $NIC"

    reset_tc $NIC
    tc filter add dev $NIC root prio 1 protocol ip matchall skip_sw action police rate 1mbit burst 20k && \
        err "Expected to fail on uplink rep"
    reset_tc $NIC
}


enable_switchdev
test_basic_matchall_rep
test_basic_matchall_uplink_rep
check_kasan
test_done
