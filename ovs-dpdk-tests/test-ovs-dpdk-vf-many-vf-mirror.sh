#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with many local mirroring
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

IP2=1.1.1.15

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $IP2

    ovs-ofctl add-flow br-phy "in_port=pf0,actions=pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf0"
    ovs-ofctl add-flow br-phy "in_port=pf0vf0,actions=pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0"
}

function run() {
    config
    config_remote_nic

    t=5
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
    check_offload_contains "0x0800.*pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf0," 1
    check_offload_contains "0x0800.*pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0vf1,pf0," 1
}

run
trap - EXIT
cleanup_test
test_done
