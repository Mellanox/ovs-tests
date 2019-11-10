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
    # testing on rep and uplink rep
    for nic in $REP $NIC ; do
        title "Test matchall rule on rep $nic"

        reset_tc $nic
        tc_filter add dev $nic root prio 1 protocol ip matchall skip_sw action police rate 1mbit burst 20k
        tc filter show dev $nic ingress
        reset_tc $nic
    done
}


enable_switchdev
test_basic_matchall
check_kasan
test_done
