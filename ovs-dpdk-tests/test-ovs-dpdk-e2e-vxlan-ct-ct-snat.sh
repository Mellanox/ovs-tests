#!/bin/bash
#
# Test OVS with vxlan traffic and CT-CT-SNAT rules
#
# E2E-CACHE
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

REMOTE=1.1.1.8

VXLAN_MAC=e4:11:22:33:44:55
SNAT_IP=5.5.1.1
SNAT_ROUTE=5.5.1.0

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ip netns exec ns0 ip r a $SNAT_ROUTE/24 dev $VF
    ip netns exec ns0 arp -s $SNAT_IP $VXLAN_MAC
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
    ovs-ofctl add-flow br-int "arp,actions=normal"
    ovs-ofctl add-flow br-int "icmp,actions=normal"
    ovs-ofctl add-flow br-int "table=0,ip,ct_state=-trk,actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+new,actions=ct(commit,nat(src=${SNAT_IP}:2000-2010)),normal"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+est,actions=ct(nat),normal"
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
trap - EXIT
cleanup_test
test_done
