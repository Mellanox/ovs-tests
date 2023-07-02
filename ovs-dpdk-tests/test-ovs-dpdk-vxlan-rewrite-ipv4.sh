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
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ip netns exec ns0 ip r a $FAKE_ROUTE/24 dev $VF
    ip netns exec ns0 arp -s $FAKE_IP $VXLAN_MAC
    on_remote ip l set dev $TUNNEL_DEV address $VXLAN_MAC
}

function add_openflow_rules() {
    debug "Adding ipv4 rewrite openflow rules"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=normal"
    ovs-ofctl add-flow br-int "icmp,actions=normal"
    ovs-ofctl add-flow br-int "table=0,in_port=vxlan_br-int,ip,actions=mod_nw_src=$FAKE_IP,$IB_PF0_PORT0"
    ovs-ofctl add-flow br-int "table=0,in_port=$IB_PF0_PORT0,ip,actions=mod_nw_dst=$REMOTE_IP,vxlan_br-int"
    debug "openflow rules:"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
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
