#!/bin/bash
#
# Bug SW #1718378: [upstream] syndrome (0x563e2f) followed by kernel panic during VF mirroring under stress traffic.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4

config_sriov 3
enable_switchdev
REP3=`get_rep 2`

function test1() {
    title "Add mirror rule"
    reset_tc $REP
    tc_filter_success add dev $REP ingress protocol arp prio 1 flower skip_sw \
        action mirred egress mirror dev $REP2 pipe \
        action mirred egress redirect dev $REP3
    reset_tc $REP
}

function test2() {
    title "Add mirror rule with duplicate destination (expected to fail)"
    reset_tc $REP
    tc filter add dev $REP ingress protocol arp prio 1 flower skip_sw \
        action mirred egress mirror dev $REP2 pipe \
        action mirred egress redirect dev $REP2 && err || success
    reset_tc $REP
}


enable_switchdev
test1
test2
test_done
