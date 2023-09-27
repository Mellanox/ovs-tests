#! /usr/bin/env bash
#
# Test OVS TCP traffic with CT, CT offload disabled.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

function config() {
    cleanup_test
    ovs_set_hw_offload_ct_size 0
    start_clean_openvswitch
    config_simple_bridge_with_rep 1
    start_vdpa_vm
    config_ns ns0 $VF $LOCAL_IP
}

function cleanup() {
    ovs_cleanup_hw_offload_ct_size
    cleanup_test
}
trap cleanup EXIT

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP none false

    set_iperf2
    generate_traffic "remote" $LOCAL_IP none false
}

run

check_counters

trap - EXIT
cleanup
test_done
