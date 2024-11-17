#!/bin/bash
#
# Test OVS-DOCA openflow mod-meter
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
    local max_rate_mbits=400
    local sec=21

    config_topology

    title "Testing add meter on REPs"
    ovs_add_meter br-phy 1 kbps 100000 10000
    ovs_add_meter br-phy 2 kbps ${max_rate_mbits}000 ${max_rate_mbits}00
    ovs_add_bidir_meter_rules

    title "Generating traffic"
    local mod_meter_cmd="ovs_mod_meter br-phy 2 kbps $((max_rate_mbits * 1000 * 2))"
    local exp_bw=$((max_rate_mbits * 3 / 2))
    generate_traffic_verify_bw $sec $exp_bw "$mod_meter_cmd"

    ovs_del_meter br-phy 1
    ovs_del_meter br-phy 2
}

test_pre_config
run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
