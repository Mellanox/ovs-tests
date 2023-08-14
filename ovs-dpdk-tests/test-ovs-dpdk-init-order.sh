#!/bin/bash

# This test will yield some OVS errors which are expected.
# This is testing OVS configuration in the wrong order meaning
# having reps configured first and then the PF.
# After adding the PF we expect everything to work normally.

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2 false
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function verify_err_and_add_pf() {
    local pci=$(get_pf_pci)
    local msg="Resource temporarily unavailable"

    verify_ovs_expected_msg "$msg"
    ovs_add_port "PF"
}

function run() {
    config

    verify_err_and_add_pf

    verify_ping

    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
