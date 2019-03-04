#!/bin/bash
#
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
    reset_tc_nic $REP

    title "Add TC mirred rule from $REP to $vlan_dev"
    tc_filter add dev $REP protocol ip ingress prio 1 flower skip_sw \
        dst_mac e4:11:22:33:44:70 ip_proto udp \
        action mirred egress redirect dev $vlan_dev
    reset_tc_nic $REP

    reset_tc_nic $vlan_dev
    title "Add TC mirred rule from $vlan_dev to $REP"
    tc_filter add dev $vlan_dev protocol ip ingress prio 1 flower \
        dst_mac e4:11:22:33:44:60 ip_proto udp \
        action mirred egress redirect dev $REP
    tc filter show dev $vlan_dev ingress prio 1 | grep -q -w in_hw || err "$vlan_dev->$REP rule not in hw"
    reset_tc_nic $vlan_dev

    ip l del dev $vlan_dev
}

run
test_done
