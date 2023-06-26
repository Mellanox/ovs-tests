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
require_interfaces REP NIC
unbind_vfs
bind_vfs

VLAN_ID=7
VLAN_DEV=${VF}.${VLAN_ID}

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $TUNNEL_ID $REMOTE_TUNNEL_IP
    config_vlan_device_ns $VF $VLAN_DEV $VLAN_ID $LOCAL_IP $LOCAL_IP "ns0"
    debug "Removing $VF ip address"
    ip netns exec ns0 ifconfig $VF 0
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function add_openflow_rules() {
    debug "Adding openflow rules"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "in_port=vxlan_br-int,actions=push_vlan:0x8100,mod_vlan_vid:7, output:$IB_PF0_PORT0" -O OpenFlow11
    ovs-ofctl add-flow br-int "in_port=$IB_PF0_PORT0,dl_vlan=7,actions=pop_vlan, output:vxlan_br-int" -O OpenFlow11
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote_tunnel "vxlan"
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
