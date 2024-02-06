#!/bin/bash
#
# Test OVS-DPDK ctnat-ct
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

DUMMY_IP=1.1.1.111

trap cleanup_test EXIT

function config() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    debug "Restarting OVS"
    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    config_static_arp_ns ns0 ns1 $VF $DUMMY_IP
}

function run() {
    config
    ovs_add_ct_after_nat_rules br-phy $LOCAL_IP $DUMMY_IP $IB_PF0_PORT1 $IB_PF0_PORT0
    verify_ping
    generate_traffic local $DUMMY_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
