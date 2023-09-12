#!/bin/bash
#
# Test OVS-DPDK ICNP traffic with match on icmp_type and icmp_code
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
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "icmp,actions=move:icmp_type->NXM_NX_XXREG0[0..7],move:icmp_code->NXM_NX_XXREG1[0..7],NORMAL"
    ovs_ofctl_dump_flows
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping

    sleep_time=0.5
    validate_offload $LOCAL_IP
}

run

trap - EXIT
cleanup_test
test_done
