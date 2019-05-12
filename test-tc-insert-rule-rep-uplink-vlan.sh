#!/bin/bash
#
# Bug SW #974864: ping between VMs cause null deref
# Bug SW #1583139: Crash adding tc mirred rule between rep and uplink vlan
# Task #1695130: Upstream 5.2: VLAN uplink
#
# Try to add tc mirred rule from rep to uplink vlan
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces REP NIC

function run() {
    vlan=5
    vlan_dev=${NIC}.$vlan

    ip link add link $NIC name $vlan_dev type vlan id $vlan

    title "Add TC mirred rule from $REP to $vlan_dev"
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip ingress prio 10 flower \
        dst_mac e4:11:22:33:44:70 ip_proto udp \
        action mirred egress redirect dev $vlan_dev
    verify_in_hw $REP 10

    title "Add TC mirred rule from $vlan_dev to $REP"
    reset_tc_nic $vlan_dev
    tc_filter add dev $vlan_dev protocol ip ingress prio 11 flower \
        dst_mac e4:11:22:33:44:60 ip_proto udp \
        action mirred egress redirect dev $REP
    verify_in_hw $vlan_dev 11

    reset_tc_nic $REP
    ip l del dev $vlan_dev
}

run
test_done
