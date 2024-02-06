#!/bin/bash
#
# Test OVS-DPDK with TCP traffic with CT
#
# E2E-CACHE
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

IP=1.1.1.7
IP2=1.1.1.8

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm1
    start_vdpa_vm2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1
    check_e2e_stats
}

run
trap - EXIT
cleanup_test
test_done
