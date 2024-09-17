#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

add_expected_error_for_issue 4016359 "failed to add 1 connection offloads"

function cleanup() {
    clear_ns_dev ns0 int0
    clear_ns_dev ns1 br-phy
    cleanup_test
}

trap cleanup EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 0
    ovs-vsctl add-port br-phy int0 -- set interface int0 type=internal
    config_ns ns0 int0 $LOCAL_IP
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
