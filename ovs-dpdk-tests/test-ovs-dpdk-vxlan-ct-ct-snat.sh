#!/bin/bash
#
# Test OVS with vxlan traffic and CT-CT-SNAT rules
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

VXLAN_MAC=e4:11:22:33:44:55
SNAT_IP=5.5.1.1
SNAT_ROUTE=5.5.1.0

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    enable_ct_ct_nat_offload
    debug "Restarting OVS"
    restart_openvswitch

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    on_remote ip l set dev $TUNNEL_DEV address $VXLAN_MAC
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ip netns exec ns0 ip r a $SNAT_ROUTE/24 dev $VF
    ip netns exec ns0 arp -s $SNAT_IP $VXLAN_MAC
}

function add_openflow_rules() {
    ovs-ofctl add-flow br-int "arp,actions=normal"
    ovs-ofctl add-flow br-int "icmp,actions=normal"
    ovs-ofctl add-flow br-int "table=0,ip,ct_state=-trk,actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+new,actions=ct(commit,nat(src=${SNAT_IP}:2000-2010)),normal"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+est,actions=ct(nat),normal"
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
trap - EXIT
cleanup_test
test_done
