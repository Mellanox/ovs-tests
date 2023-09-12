#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with local mirroring
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

IP2=1.1.1.15

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 1
    add_local_mirror mirror 1 br-phy
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $IP2
}

function run() {
    config
    config_remote_nic

    t=5
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
