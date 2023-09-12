#!/bin/bash
#
# Test OVS with vxlan traffic and masked-rewrite ipv4 address
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

VXLAN_MAC=e4:11:22:33:44:55
FAKE_IP=1.1.10.8
FAKE_ROUTE=1.1.10.0

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    debug "Restarting OVS"
    restart_openvswitch

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ip netns exec ns0 ip r a $FAKE_ROUTE/24 dev $VF
    ip netns exec ns0 arp -s $FAKE_IP $VXLAN_MAC
    on_remote ip l set dev $TUNNEL_DEV address $VXLAN_MAC
}

function add_openflow_rules() {
    local bridge="br-int"
    debug "Adding ipv4 rewrite openflow rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "icmp,actions=normal"
    ovs-ofctl -O openflow13 add-flow $bridge "table=0,in_port=vxlan_$bridge,ip,actions=set_field:$FAKE_IP/255.255.255.0->ip_src,$IB_PF0_PORT0"
    ovs-ofctl -O openflow13 add-flow $bridge "table=0,in_port=$IB_PF0_PORT0,ip,actions=set_field:$REMOTE_IP/255.255.255.0->ip_dst,vxlan_$bridge"
    debug "openflow rules:"
    ovs-ofctl -O openflow13 dump-flows $bridge --color
}

function run() {
    config
    add_openflow_rules

    # icmp
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
