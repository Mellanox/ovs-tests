#!/bin/bash
#
# Testing QinQ by adding rules to TC in NIC mode. expected to fail as not supported.
#
# [Kernel Upstream] Bug SW #2616303: syndrome adding cvlan rule in legacy mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_legacy
require_interfaces NIC

function tc_filter_fail() {
    eval tc -s filter $@ && err "Expected to fail adding rule"
}

function __test_test_simple_cvlan() {
    reset_tc $NIC

    title "- simple cvlan rule on $NIC"
    tc_filter_fail add dev $NIC protocol 802.1ad parent ffff: pref 110 \
        flower skip_sw vlan_ethtype 802.1q cvlan_ethtype ip ip_proto tcp \
        dst_ip 10.141.10.2 dst_port 24 vlan_id 100 action drop

    reset_tc $NIC
}

function __test_qinq_double_push_no_pop() {
    reset_tc $NIC

    title "- vlan double push rule on nic:$NIC"
    tc_filter_fail add dev $NIC protocol arp parent ffff: prio 1 \
        flower skip_sw \
        action vlan push id 6 \
        action vlan push protocol 802.1ad id 1000 action drop

    title "- vlan no pop rule on nic:$NIC"
    tc_filter_fail add dev $NIC protocol 802.1ad parent ffff: prio 2 \
        flower skip_sw \
        vlan_id 1000  \
        vlan_ethtype 802.1q cvlan_id 6 \
        cvlan_ethtype arp \
        action drop

    reset_tc $NIC
}

function run_tests() {
    title "Try to add tc rules on nic mode and expect to fail without a syndrome"
    __test_test_simple_cvlan
    __test_qinq_double_push_no_pop
}

start_check_syndrome
run_tests
title "Check for errors"
check_syndrome

test_done
