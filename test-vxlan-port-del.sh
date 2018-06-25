#!/bin/bash
#
# Test that verified DELETE_VXLAN_UDP_DPORT syndrome
#
# Bug SW #989230: DELETE_VXLAN_UDP_DPORT failed when restart ovs in vxlan with
# non-default port
#
# Bug SW #1008211: Call trace from vxlan_dellink() when deleting the interface after down

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


NON_STANDARD_PORT=1234
IFACE=vxlan1
ip link del $IFACE >/dev/null 2>&1


function test_up_del() {
    title "-- up/del"
    start_check_syndrome
    ip link add $IFACE type vxlan dstport $NON_STANDARD_PORT external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set $IFACE up
    ip link del $IFACE
    check_syndrome || err
    check_kasan && success || err
}

function test_up_down_del() {
    title "-- up/down/del"
    start_check_syndrome
    ip link add $IFACE type vxlan dstport $NON_STANDARD_PORT external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set $IFACE up
    ip link set $IFACE down
    sleep 1
    ip link del $IFACE
    check_syndrome || err
    check_kasan && success || err
}


title "Test for DELETE_VXLAN_UDP_DPORT"
test_up_del
test_up_down_del
test_done
