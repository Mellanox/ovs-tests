#!/bin/bash
#
# Test goto chain
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function test_goto_fwd() {
    title "Test goto fwd"

    reset_tc $REP
    tc_filter add dev $REP root prio 1 chain 1 protocol ip flower skip_sw action goto chain 5
    reset_tc $REP
}

function test_goto_back() {
    title "Test goto back"

    reset_tc $REP
    tc_filter add dev $REP root prio 1 chain 5 protocol ip flower skip_sw action goto chain 1
    reset_tc $REP
}

enable_switchdev
test_goto_fwd
test_goto_back
check_kasan
test_done
