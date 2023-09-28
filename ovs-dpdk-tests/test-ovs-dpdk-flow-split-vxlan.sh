#!/bin/bash
#
# Test OVS with vxlan traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function add_openflow_rules() {
    NIC_MAC=`cat /sys/class/net/$NIC/address`
    REMOTE_NIC_MAC=`on_remote cat /sys/class/net/$REMOTE_NIC/address`
    VF_MAC=$(ip netns exec ns0 cat /sys/class/net/$VF/address)
    REMOTE_MAC=`on_remote cat /sys/class/net/$TUNNEL_DEV/address`
    debug "Adding openflow rules including a long match vxlan tunnel rule"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=normal"
    ovs-ofctl add-flow br-int "icmp,actions=normal"
    ovs-ofctl add-flow br-int "table=0,in_port=vxlan_br-int,tun_eth_src=$REMOTE_NIC_MAC,tun_eth_dst=$NIC_MAC,dl_src=$REMOTE_MAC,dl_dst=$VF_MAC,ip,nw_dst=$LOCAL_IP,nw_src=$REMOTE_IP,actions=$IB_PF0_PORT0"
    ovs-ofctl add-flow br-int "table=0,in_port=$IB_PF0_PORT0,ip,actions=vxlan_br-int"
}

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    add_openflow_rules
}

function run() {
    config

    # icmp
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
