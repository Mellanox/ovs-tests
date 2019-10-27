#!/bin/bash
#
# Bug SW #1718378: [upstream] syndrome (0x563e2f) followed by kernel panic during VF mirroring under stress traffic.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

config_sriov 3
enable_switchdev_if_no_rep $REP
REP3=`get_rep 2`

function tc_filter() {
    eval2 tc filter $@ && success
}

function test1() {
    title "Add mirror rule"
    reset_tc $REP
    tc_filter add dev $REP ingress protocol arp prio 1 flower skip_sw \
        action mirred egress mirror dev $REP2 pipe \
        action mirred egress redirect dev $REP3
    reset_tc $REP
}

function test2() {
    title "Add mirror rule with duplicate destination"
    reset_tc $REP
    tc_filter add dev $REP ingress protocol arp prio 1 flower skip_sw \
        action mirred egress mirror dev $REP2 pipe \
        action mirred egress redirect dev $REP2
    reset_tc $REP
}


start_check_syndrome
enable_switchdev
test1
test2
check_kasan
check_syndrome
test_done
