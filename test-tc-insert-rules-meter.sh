#!/bin/bash
#
# Test police action
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5

require_module act_ct act_police

POLICE_INDEX=999

function reset_tc_and_delete_police_action() {
    local dev=$1

    reset_tc $dev
    sleep 0.1
    tc action delete action police index $POLICE_INDEX
}

function test_basic_meter() {
    local dev=$1
    local out_dev=$2

    title "Test basic meter ($dev -> $out_dev)"

    title "  - rule with one police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with two police actions"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action police rate 200mbit burst 12m conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with three police actions"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action police rate 200mbit burst 12m conform-exceed drop/pipe \
        action police rate 300mbit burst 12m conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with max rate/burst police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 2047999999999 burst 4294967295 conform-exceed drop/pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with ct before police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        dst_mac 20:22:33:44:55:66 \
        ct_state -trk \
        action ct \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action goto chain 1

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with ct after police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        dst_mac 20:22:33:44:55:66 \
        ct_state -trk \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action ct \
        action goto chain 1

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - rule with pedit after police action"
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 100mbit burst 12m conform-exceed drop/pipe \
        action pedit ex munge eth dst set 20:22:33:44:55:66 pipe \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc $dev

    title "  - one rule uses one police index"
    tc action add police rate 100mbit burst 12m conform-exceed drop/pipe index $POLICE_INDEX
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police index $POLICE_INDEX \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc_and_delete_police_action $dev

    title "  - two rules use one police index"
    tc action add police rate 100mbit burst 12m conform-exceed drop/pipe index $POLICE_INDEX
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police index $POLICE_INDEX \
        action mirred egress redirect dev $out_dev

    tc_filter add dev $dev ingress protocol ip prio 3 flower \
        action police index $POLICE_INDEX \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    verify_in_hw $dev 3
    reset_tc_and_delete_police_action $dev

    title "  - one rule uses one police action and one police index"
    tc action add police rate 100mbit burst 12m conform-exceed drop/pipe index $POLICE_INDEX
    tc_filter add dev $dev ingress protocol ip prio 2 flower \
        action police rate 200mbit burst 12m conform-exceed drop/pipe \
        action police index $POLICE_INDEX \
        action mirred egress redirect dev $out_dev

    verify_in_hw $dev 2
    reset_tc_and_delete_police_action $dev
}

function test_multiple_meters() {
    local dev=$1
    local out_dev=$2
    local count=$3

    title "Test insert $count rules with meter ($dev -> $out_dev)"
    reset_tc $dev
    for i in `seq $count`
    do
        tc_filter add dev $dev ingress protocol ip prio 2 flower \
            dst_ip 1.1.1.${i} \
            action police rate 100mbit burst 12m conform-exceed drop/pipe \
            action mirred egress redirect dev $out_dev
    done

    reset_tc $dev
}

config_sriov 2
enable_switchdev
bind_vfs

test_basic_meter $NIC $REP
test_basic_meter $REP $NIC
test_basic_meter $REP $REP2
test_multiple_meters $NIC $REP 200
test_multiple_meters $REP $NIC 200
test_multiple_meters $REP $REP2 200

test_done
