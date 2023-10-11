#!/bin/bash
#
# Test OVS-DPDK openflow meters
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function test_pre_config() {
    config_sriov 2
    require_interfaces REP NIC
    enable_switchdev
    bind_vfs

    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch
}

function config_topology() {
    config_simple_bridge_with_rep 2

    config_ns ns0 $VF1 $REMOTE_IP
    config_ns ns1 $VF2 $LOCAL_IP
}

function run() {
    local max_rate_mbits=100
    local sec=15

    config_topology

    title "Testing add meter on REPs"
    ovs_add_meter br-phy 1 kbps 400000 200000
    ovs_add_meter br-phy 2 kbps 200000 100000
    ovs_add_meter br-phy 3 kbps ${max_rate_mbits}000 $((max_rate_mbits/2))000

    ovs_add_multi_meter_rules

    title "Generating traffic"
    generate_traffic_verify_bw $sec $max_rate_mbits

    ovs_del_meter br-phy 1
    ovs_del_meter br-phy 2
    ovs_del_meter br-phy 3
}

test_pre_config
run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
