#!/bin/bash
#
# Test OVS-DPDK with TCP traffic and
# CT-CT-DNAT rules
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
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable false
    enable_ct_ct_nat_offload
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP_2
    sleep 2
    config_static_arp_ns ns0 ns1 $VF $FAKE_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep1,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat(dst=4.4.4.10:5201)),rep0"
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

    generate_traffic "local" $FAKE_IP ns1

    # check offloads
    check_dpdk_offloads $IP
    check_offloaded_connections 5
}

run
start_clean_openvswitch
test_done
