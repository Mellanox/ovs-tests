#!/bin/bash
#
# Testing QinQ by adding rules to TC
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
require_interfaces NIC REP

function __test_qinq_double_pushpop() {
    local skip=$1

    title "- Setting rule on nic:$REP skip:$skip"
    reset_tc $NIC
    reset_tc $REP

    title "    - vlan double push"
    tc_filter_success add dev $REP protocol arp parent ffff: prio 1 \
        flower \
        $skip \
        action vlan push id 6 \
        action vlan push protocol 802.1ad id 1000 action mirred egress redirect dev $NIC

    title "- Setting rule on nic:$NIC skip:$skip"
    title "    - vlan double pop"
    tc_filter_success add dev $NIC protocol 802.1ad parent ffff: prio 2 \
        flower \
        $skip \
        vlan_id 1000  \
        vlan_ethtype 802.1q cvlan_id 6 \
        cvlan_ethtype arp \
        action vlan pop \
        action vlan pop \
        action mirred egress redirect dev $REP

    reset_tc $NIC
    reset_tc $REP
}

function __test_qinq_double_push_one_pop() {
    local skip=$1

    title "- Setting rule on nic:$REP skip:$skip"
    reset_tc $NIC
    reset_tc $REP

    title "    - vlan double push"
    tc_filter_success add dev $REP protocol arp parent ffff: prio 1 \
        flower \
        $skip \
        action vlan push id 6 \
        action vlan push protocol 802.1ad id 1000 action mirred egress redirect dev $NIC

    title "- Setting rule on nic:$NIC skip:$skip"
    title "    - vlan pop"
    tc_filter_success add dev $NIC protocol 802.1ad parent ffff: prio 2 \
        flower \
        $skip \
        vlan_id 1000  \
        vlan_ethtype 802.1q cvlan_id 6 \
        cvlan_ethtype arp \
        action vlan pop \
        action mirred egress redirect dev $REP

    reset_tc $NIC
    reset_tc $REP
}


function __test_qinq_double_push_no_pop() {
    local skip=$1

    title "- Setting rule on nic:$REP skip:$skip"
    reset_tc $NIC
    reset_tc $REP

    title "    - vlan double push"
    tc_filter_success add dev $REP protocol arp parent ffff: prio 1 \
        flower \
        $skip \
        action vlan push id 6 \
        action vlan push protocol 802.1ad id 1000 action mirred egress redirect dev $NIC

    title "- Setting rule on nic:$NIC skip:$skip"
    title "    - vlan no pop"
    tc_filter_success add dev $NIC protocol 802.1ad parent ffff: prio 2 \
        flower \
        $skip \
        vlan_id 1000  \
        vlan_ethtype 802.1q cvlan_id 6 \
        cvlan_ethtype arp \
        action mirred egress redirect dev $REP

    reset_tc $NIC
    reset_tc $REP
}

function test_qinq_double_pushpop() {
    local skip
    for skip in "" skip_hw skip_sw; do
        __test_qinq_double_pushpop $skip
    done
}

function test_qinq_double_push_one_pop() {
    local skip
    for skip in "" skip_hw skip_sw; do
        __test_qinq_double_push_one_pop $skip
    done
}

function test_qinq_double_push_no_pop() {
    local skip
    for skip in "" skip_hw skip_sw; do
        __test_qinq_double_push_no_pop $skip
    done
}

start_check_syndrome

# Execute all test* functions

test_qinq_double_push_no_pop
test_qinq_double_push_one_pop
test_qinq_double_pushpop

check_syndrome

test_done
