#!/bin/bash
#
# Test OVS with vxlan traffic with remote mirroring
# as a Geneve tunnel and CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

MIRROR_IP=8.8.8.8
DUMMY_IP=8.8.8.10

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    add_remote_mirror geneve br-int 150 $DUMMY_IP $MIRROR_IP
}

function add_openflow_rules() {
    ovs_add_ct_rules br-int
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
