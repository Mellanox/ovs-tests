#!/bin/bash
#
# Bug SW #974864: ping between VMs cause null deref
# Bug SW #1583139: Crash adding tc mirred rule between rep and uplink vlan
#
# Try to add tc mirred rule from rep to uplink vlan
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces REP NIC

function run() {
    vlan=5
    vlan_dev=${NIC}.$vlan

    title "Add TC mirred rule from $REP to $vlan_dev"

    ip link add link $NIC name $vlan_dev type vlan id $vlan
    reset_tc_nic $REP

    tc_filter add dev $REP protocol ip ingress prio 10 flower \
        dst_mac e4:11:22:33:44:70 ip_proto udp \
        action mirred egress redirect dev $vlan_dev

    reset_tc_nic $REP
    ip l del dev $vlan_dev
}

run
test_done
