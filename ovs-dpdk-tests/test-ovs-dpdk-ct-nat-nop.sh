#!/bin/bash
#
# Test OVS-DPDK CT with an empty nat action using TCP traffic
#
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=4.4.4.10
IP_2=4.4.4.11

trap cleanup_test EXIT

function config() {
    enable_switchdev
    bind_vfs
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP_2
}

function run() {
    config
    ovs_add_ct_nat_nop_rules br-phy
    verify_ping $IP_2 ns0
    # traffic
    generate_traffic "local" $IP ns1
    # check offloads
    check_dpdk_offloads $IP
    check_offloaded_connections 5
}

run
start_clean_openvswitch
test_done
