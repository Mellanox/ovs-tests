#!/bin/bash
#
# Bug SW #2226643: VF mirror with vlan pop for only one of the VF isn't offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

config_sriov 2
enable_switchdev

function test1() {
    title "Add mirror rule"
    reset_tc $NIC
    tc_filter_success add dev $NIC ingress protocol 802.1q flower \
        vlan_id 10 vlan_ethtype 802.1q cvlan_id 5 \
        action mirred egress mirror dev $REP2 pipe \
        action vlan pop action vlan pop \
        action mirred egress redirect dev $REP
    reset_tc $NIC
}

start_check_syndrome
enable_switchdev
test1
check_syndrome
test_done
