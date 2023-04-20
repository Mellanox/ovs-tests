#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a Geneve tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

DUMMY_IP=8.8.8.8
MIRROR_IP=8.8.8.7

config_sriov 2
enable_switchdev
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
    config_remote_bridge_tunnel $TUNNEL_ID $REMOTE_TUNNEL_IP vxlan 2
    add_remote_mirror geneve br-int 150 $DUMMY_IP $MIRROR_IP
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function run() {
    config
    config_remote

    t=5
    verify_ping $LOCAL_IP ns1

    generate_traffic "local" $LOCAL_IP ns1
}

run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
