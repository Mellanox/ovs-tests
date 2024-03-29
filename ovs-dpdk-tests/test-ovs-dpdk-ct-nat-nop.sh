#!/bin/bash
#
# Test OVS-DPDK CT with an empty nat action using TCP traffic
#
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function config() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function run() {
    config
    ovs_add_ct_nat_nop_rules br-phy
    verify_ping $REMOTE_IP ns0
    # traffic
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
