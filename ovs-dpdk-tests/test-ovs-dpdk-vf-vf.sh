#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function run() {
    config

    verify_ping $REMOTE_IP ns0
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
