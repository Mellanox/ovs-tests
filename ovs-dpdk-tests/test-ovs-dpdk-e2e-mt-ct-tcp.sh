#!/bin/bash
#
# Test OVS-DPDK with TCP traffic with CT and e2e-cache enabled in which
# insertion is done in both the e2e-cache and multi-tables
#
# E2E-CACHE
#
# Bug SW #3541222: [BF2,OVS-DPDK,Ubuntu20.04] - OVS got error core dumped (Segmentation fault) after DPIX (connection tracking insertion) testing
# Bug SW #3696162: [ovs-dpdk] e2e-cache flows are wrongly aged | Assignee: Salem Sol | Status: Assigned

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

function cleanup() {
    ovs_clear_datapaths
    cleanup_test
}

trap cleanup EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    ovs_conf_set e2e-size 3
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm1
    start_vdpa_vm2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP

    # ct zone used in ovs_add_ct_rules
    local ct_zone=5
    ovs_set_ct_zone_timeout $ct_zone "tcp" 30
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1 true "ns0" "local" 60
    ovs_conf_remove e2e-size
}

run
trap - EXIT
cleanup
test_done
