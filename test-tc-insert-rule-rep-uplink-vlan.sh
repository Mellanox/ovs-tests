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

enable_switchdev
require_interfaces REP NIC

function verify_hw_rules() {
    title "verify hw rules"
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i > /tmp/port$i --no_zero || err "mlxdump failed"

    # expect action count+fwd+vlan_pop
    grep -B7 "outer_headers.dmac_47_16.*:0xe4112233" /tmp/port0 | grep -q "action.*:0x8c"
    if [ $? != 0 ]; then
        err "Invalid action in hw rule for vlan pop"
    fi

    # expect action count+fwd+vlan_push
    grep -B10 "outer_headers.dmac_47_16.*:0xe4667788" /tmp/port0 | grep -q "action.*:0x10c"
    if [ $? != 0 ]; then
        err "Invalid action in hw rule for vlan push"
    fi
}

function run() {
    vlan=5
    vlan_dev=${NIC}.$vlan

    ip link add link $NIC name $vlan_dev type vlan id $vlan
    reset_tc $REP $vlan_dev

    title "Add TC mirred rule from $REP to $vlan_dev"
    tc_filter add dev $REP protocol ip ingress prio 10 flower \
        dst_mac e4:66:77:88:44:70 ip_proto udp \
        action mirred egress redirect dev $vlan_dev
    verify_in_hw $REP 10


    title "Add TC mirred rule from $vlan_dev to $REP"
    tc_filter add dev $vlan_dev protocol ip ingress prio 11 flower \
        dst_mac e4:11:22:33:44:60 ip_proto udp \
        action mirred egress redirect dev $REP
    verify_in_hw $vlan_dev 11

    mode=`get_flow_steering_mode $NIC`
    if [ "$mode" == "dmfs" ]; then
        verify_hw_rules
    fi

    title "Add TC drop rule on $vlan_dev"
    reset_tc $vlan_dev
    tc_filter add dev $vlan_dev protocol ip ingress prio 11 flower \
        dst_mac e4:11:22:33:44:60 ip_proto udp \
        action drop
    verify_in_hw $vlan_dev 11

    reset_tc $REP
    ip l del dev $vlan_dev
}

run
test_done
