#!/bin/bash
#
# Test OVS with vxlan traffic with remote mirroring
# as a Geneve tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

MIRROR_IP=8.8.8.8
DUMMY_IP=8.8.8.10

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    add_remote_mirror geneve br-int 150 $DUMMY_IP $MIRROR_IP
}

function run() {
    config

    # icmp
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
