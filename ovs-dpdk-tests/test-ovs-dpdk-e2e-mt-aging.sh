#!/bin/bash
#
# Test OVS-DPDK E2E-CACHE MT aging
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=1.1.1.7
IP2=1.1.1.8

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_e2e_cache
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable true
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP2
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"
    debug "\nOVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    generate_traffic "local" $IP ns1
    check_e2e_stats 10
}

run
start_clean_openvswitch
test_done
