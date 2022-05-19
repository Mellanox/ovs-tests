#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a VXLAN tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
IP2=1.1.1.15

REMOTE_IP=7.7.7.8
VXLAN_ID=42
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

    config_tunnel "vxlan" 2
    add_remote_mirror vxlan br-int 150 $DUMMY_IP $MIRROR_IP
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns1 $VF2 $IP2
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
    debug "\nTesting Ping"
    verify_ping $IP ns1

    debug "\nTesting TCP traffic"
    generate_traffic "local" $IP ns1

    # check offloads
    check_dpdk_offloads $IP
}

run
start_clean_openvswitch
test_done
