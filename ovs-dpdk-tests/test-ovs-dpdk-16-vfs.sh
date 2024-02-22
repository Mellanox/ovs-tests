#!/bin/bash
#
# Test OVS-DPDK with 16 VFs
#
# Bug SW #3574397: can't open more than 6 ports with HWS
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 16
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup EXIT

function cleanup() {
    cleanup_test
    remote_cleanup_test
}

function config() {
    cleanup
    config_simple_bridge_with_rep 16
    config_ns ns0 $VF $LOCAL_IP
}

function run() {
    config
    config_remote_nic

    verify_ping
    generate_traffic "remote" $LOCAL_IP

    set_iperf2
    generate_traffic "remote" $LOCAL_IP

    ovs_clear_bridges
    config_sriov 2
}

run
check_counters
trap - EXIT
cleanup
test_done
