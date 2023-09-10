#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 0
    ovs-vsctl add-port br-phy int -- set interface int type=internal
    config_ns ns0 int $LOCAL_IP
    config_ns ns1 br-phy $REMOTE_IP
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy ip
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1 "false"
}

run
trap - EXIT
cleanup_test
test_done
