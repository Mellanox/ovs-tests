#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a VXLAN tunnel
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

    config_tunnel "vxlan" 2
    add_remote_mirror vxlan br-int 150 $DUMMY_IP $MIRROR_IP
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns1 $VF2 $REMOTE_IP
}

function run() {
    config
    config_remote_nic $DUMMY_IP

    verify_ping $LOCAL_IP ns1

    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
