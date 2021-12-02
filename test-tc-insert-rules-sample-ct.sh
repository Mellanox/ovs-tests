#!/bin/bash
#
# Test insert rule SAMPLE+CT
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct act_sample psample

config_sriov
enable_switchdev
require_interfaces REP

function run() {
    title "Test SAMPLE+CT"
    tc_test_verbose

    local group=5
    local rate=1
    local trunc=60
    local mac="e4:11:11:11:11:11"

    reset_tc $REP

    tc_filter add dev $REP ingress protocol ip prio 2 flower $tc_verbose \
        dst_mac $mac ct_state -trk \
        action sample rate $rate group $group trunc $trunc \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip prio 3 flower $tc_verbose \
        dst_mac $mac ct_state -trk \
        action sample rate $rate group $group trunc $trunc \
        action ct nat action goto chain 1

    echo $REP
    tc filter show dev $REP ingress

    verify_in_hw $REP 2
    verify_not_in_hw $REP 3

    reset_tc $REP
}


run
test_done
