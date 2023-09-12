#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 1
    start_vdpa_vm
    config_ns ns0 $VF $LOCAL_IP
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP

    set_iperf2
    generate_traffic "remote" $LOCAL_IP
}

run

check_counters

trap - EXIT
cleanup_test
test_done
