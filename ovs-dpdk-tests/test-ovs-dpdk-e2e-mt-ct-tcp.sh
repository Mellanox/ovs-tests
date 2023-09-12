#!/bin/bash
#
# Test OVS-DPDK with TCP traffic with CT and e2e-cache enabled in which
# insertion is done in both the e2e-cache and multi-tables
#
# E2E-CACHE
#
# Bug SW #3541222: [BF2,OVS-DPDK,Ubuntu20.04] - OVS got error core dumped (Segmentation fault) after DPIX (connection tracking insertion) testing

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    ovs_conf_set e2e-size 2
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
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
    ovs_conf_remove e2e-size
}

run
trap - EXIT
cleanup_test
test_done
