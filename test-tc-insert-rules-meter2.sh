#!/bin/bash
#
# Test police action
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5

require_module act_ct act_police

function test_basic_meter() {
    local dev=$1
    local out_dev=$2

    title "Test basic meter ($dev -> $out_dev)"

    title "  - rule with four police actions"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action police rate 200mbit burst 12m conform-exceed drop/pipe \
        action police rate 300mbit burst 12m conform-exceed drop/pipe \
        action police rate 400mbit burst 12m conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with pedit before police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action pedit ex munge eth dst set 20:22:33:44:55:66 pipe \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev
}

config_sriov 2
enable_switchdev
bind_vfs

test_basic_meter $NIC $REP
test_basic_meter $REP $NIC
test_basic_meter $REP $REP2

test_done
