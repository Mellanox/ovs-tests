#!/bin/bash
#
# Test OVS with vxlan traffic and rewrite ipv4 address
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

VXLAN_MAC=e4:11:22:33:44:55
FAKE_IP=5.5.1.1
FAKE_ROUTE=5.5.1.0

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    enable_ct_ct_nat_offload
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ip netns exec ns0 ip r a $FAKE_ROUTE/24 dev $VF
    ip netns exec ns0 arp -s $FAKE_IP $VXLAN_MAC
}

function config_remote() {
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip link add $TUNNEL_DEV type vxlan id $TUNNEL_ID remote $LOCAL_TUN_IP dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $TUNNEL_DEV
    on_remote ip l set dev $TUNNEL_DEV address $VXLAN_MAC
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    debug "Adding ipv4 rewrite openflow rules"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=normal"
    ovs-ofctl add-flow br-int "icmp,actions=normal"
    ovs-ofctl add-flow br-int "table=0,in_port=vxlan0,ip,actions=mod_nw_src=$FAKE_IP,rep0"
    ovs-ofctl add-flow br-int "table=0,in_port=rep0,ip,actions=mod_nw_dst=$REMOTE_IP,vxlan0"
    debug "openflow rules:"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
