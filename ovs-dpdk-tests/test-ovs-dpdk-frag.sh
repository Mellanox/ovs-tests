#!/bin/bash
#
# Test OVS with fragmented traffic
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

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function validate_rules() {
    local x=$(ovs-appctl dpctl/dump-flows type=non-offloaded | grep 'eth_type(0x0800)' | grep -E '(frag=first|frag=later)' | wc -l)
    if [ "$x" != "4" ]; then
        ovs-appctl dpctl/dump-flows type=non-offloaded | grep 'eth_type(0x0800)' | grep -E '(frag=first|frag=later)'
        err "Expected to have 4 flows (first/later, 2 dirs), have $x"
    fi
}

function run() {
    config

    # icmp
    verify_ping $REMOTE_IP ns0 2000

    validate_rules
}

run
trap - EXIT
cleanup_test
test_done
