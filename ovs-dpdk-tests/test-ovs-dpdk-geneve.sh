#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
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

    config_tunnel "geneve"
    config_remote_tunnel "geneve"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function run() {
    config
    ovs-ofctl dump-flows br-int --color

    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
