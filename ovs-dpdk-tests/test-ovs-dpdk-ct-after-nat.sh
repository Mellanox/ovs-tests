#!/bin/bash
#
# Test OVS-DPDK ctnat-ct
#

my_dir="$(dirname "$0")"

. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=4.4.4.10
IP2=4.4.4.11
DUMMY_IP=4.4.4.111

trap cleanup_test EXIT

function config() {
    enable_switchdev
    bind_vfs
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns1 $VF $IP
    config_ns ns0 $VF2 $IP2
    config_static_arp_ns ns0 ns1 $VF2 $DUMMY_IP
}

function run() {
    config
    ovs_add_ct_after_nat_rules br-phy $IP2 $DUMMY_IP rep0 rep1
    generate_traffic local $DUMMY_IP ns1
    check_dpdk_offloads $IP2
    check_offloaded_connections 5
}

run
test_done
