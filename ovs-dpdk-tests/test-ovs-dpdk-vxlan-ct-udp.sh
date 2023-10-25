#!/bin/bash
#
# Test OVS-DPDK with vxlan UDP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function config_remote() {
    config_remote_tunnel "vxlan"
}

function run() {
    config
    config_remote
    ovs_add_ct_rules "br-int" "udp"

    verify_ping
    generate_scapy_traffic $VF $TUNNEL_DEV $LOCAL_IP $REMOTE_IP
}

run
trap - EXIT
cleanup_test
test_done
