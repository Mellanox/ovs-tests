#!/bin/bash
#
# Test OVS with vxlan traffic and remote mirroring
# as a VXLAN tunnel and CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
MIRROR_IP=8.8.8.8
DUMMY_IP=8.8.8.10
VXLAN_ID=42

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    add_remote_mirror vxlan br-int 150 $DUMMY_IP $MIRROR_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
    config_ns ns0 $VF $IP
}

function config_remote() {
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip link add $TUNNEL_DEV type vxlan id $VXLAN_ID remote $LOCAL_TUN dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev $TUNNEL_DEV
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "icmp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0,ip,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+est,ct_zone=5,actions=normal"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    verify_ping $REMOTE ns0

    generate_traffic "remote" $IP

    # check offloads
    check_dpdk_offloads $IP
    check_offloaded_connections 5
}

run
start_clean_openvswitch
test_done
