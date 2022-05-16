#!/bin/bash
#
# Test OVS-DPDK with TCP traffic and CT-CT-DNAT rules
#
# E2E-CACHE
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=4.4.4.10
IP_2=4.4.4.11
FAKE_IP=4.4.4.111

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
    config_ns ns1 $VF2 $IP_2
    sleep 2
    config_static_arp_ns ns0 ns1 $VF $FAKE_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep1,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat(dst=${IP}:5201)),rep0"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep0"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep0,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat),rep1"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep1"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    debug "\nTesting TCP traffic"
    generate_traffic "local" $FAKE_IP ns1

    # check offloads
    check_dpdk_offloads $IP
    check_offloaded_connections 5
}

run
start_clean_openvswitch
test_done
