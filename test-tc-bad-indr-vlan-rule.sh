#!/bin/bash
#
# Test indirect block registration doesn't add invalid vlan rules.
# [PATCH] net/mlx5e: restrict the real_dev of vlan device is the same as uplink device
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


enable_switchdev_if_no_rep $REP

vlan=5
vlan_dev=veth0.$vlan

function cleanup() {
    ip link del $vlan_dev 2>/dev/null
    ip link del veth0 2>/dev/null
    ip addr flush dev $REP
}
trap cleanup EXIT

cleanup
ip link add veth0 type veth peer name veth1
ip link add link veth0 name $vlan_dev type vlan id $vlan
reset_tc $vlan_dev

title "Add tc vlan rule veth->rep"

start_check_syndrome
tc_filter add dev $vlan_dev protocol 802.1q parent ffff: prio 1 flower \
            verbose \
            vlan_ethtype 0x800 \
            vlan_id $vlan \
            dst_mac e4:11:22:11:4a:51 \
            action vlan pop \
            action mirred egress redirect dev $REP

tc filter show dev $vlan_dev ingress prio 1 | grep -q -w in_hw && err "Found in_hw rule for veth->rep"
check_syndrome

test_done
