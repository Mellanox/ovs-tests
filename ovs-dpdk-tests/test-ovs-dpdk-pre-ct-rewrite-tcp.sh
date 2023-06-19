#!/bin/bash
#
# Test OVS-DPDK with TCP traffic and packet modify before CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

FAKE_IP=1.1.1.111

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    config_static_arp_ns ns0 ns1 $VF $FAKE_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "icmp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,tcp,nw_dst=${FAKE_IP},ct_state=-trk,actions=mod_nw_dst:${LOCAL_IP},ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,tcp,nw_src=${LOCAL_IP},ct_state=+trk+est,ct_zone=5,actions=mod_nw_src:${FAKE_IP},normal"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"

    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    verify_ping
    set_iperf2
    generate_traffic "local" $FAKE_IP ns1
}

run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
