#!/bin/bash
#
# Test OVS-DPDK with TCP traffic and
# CT-CT-DNAT rules
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

FAKE_IP=1.1.1.111

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    enable_ct_ct_nat_offload
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    sleep 2
    config_static_arp_ns ns0 ns1 $VF $FAKE_IP
}

function add_openflow_rules() {
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "icmp,actions=normal"
    ovs-ofctl add-flow $bridge "table=0,in_port=$IB_PF0_PORT1,tcp,ct_state=-trk, actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow $bridge "table=1,in_port=$IB_PF0_PORT1,tcp,ct_state=+trk+new, actions=ct(zone=2, commit, nat(dst=${LOCAL_IP}:5201)),$IB_PF0_PORT0"
    ovs-ofctl add-flow $bridge "table=1,in_port=$IB_PF0_PORT1,tcp,ct_state=+trk+est, actions=ct(zone=2, nat),$IB_PF0_PORT0"
    ovs-ofctl add-flow $bridge "table=0,in_port=$IB_PF0_PORT0,tcp,ct_state=-trk, actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow $bridge "table=1,in_port=$IB_PF0_PORT0,tcp,ct_state=+trk+new, actions=ct(zone=2, commit, nat),$IB_PF0_PORT1"
    ovs-ofctl add-flow $bridge "table=1,in_port=$IB_PF0_PORT0,tcp,ct_state=+trk+est, actions=ct(zone=2, nat),$IB_PF0_PORT1"
    ovs_ofctl_dump_flows
}

function run() {
    config
    add_openflow_rules
    verify_ping
    generate_traffic "local" $FAKE_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
