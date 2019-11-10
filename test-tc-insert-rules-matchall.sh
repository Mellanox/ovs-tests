#!/bin/bash
#
# Test basic matchall rule
#
# require cls_matchall and act_police modules.
#
# Bug SW #1909500: Rate limit is not working in openstack ( tc rule not in hw)

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function test_basic_matchall() {
    title "Test matchall rule"

    tc_filter add dev $REP root prio 1 protocol ip matchall skip_sw action police rate 1mbit burst 20k
    tc filter show dev $REP ingress
    reset_tc $REP
}


enable_switchdev
reset_tc $REP
test_basic_matchall
check_kasan
test_done
