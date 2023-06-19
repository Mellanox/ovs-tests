#!/bin/bash
#
# Test OVS-DPDK CT + ICMP traffic is not marked as offloaded, since ct icmp offload is not supported.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

trap cleanup_test EXIT

function config() {
    config_sriov 2
    enable_switchdev
    require_interfaces REP NIC
    unbind_vfs
    bind_vfs
    cleanup_test
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 1
    start_vdpa_vm
    config_ns ns0 $VF $LOCAL_IP
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,icmp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,icmp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,icmp,ct_state=+trk+est,ct_zone=5,actions=normal"
    debug "\nOVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    verify_ping
    check_offloaded_connections_marks 0 icmp
}

run

check_counters

start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
