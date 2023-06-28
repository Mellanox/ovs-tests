#!/bin/bash

# This test will yield some OVS errors which are expected.
# This will test removal of an esw manager port prior to its members.
# We expect the members to get a "Resource temporarily unavailable" Error.

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
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function del_and_add_pf() {
    local pci=$(get_pf_pci)
    local msg="Resource temporarily unavailable"

    debug "Del port pf"
    ovs-vsctl del-port pf

    verify_ovs_expected_msg "$msg"
    debug "Add port pf back"
    ovs_add_pf
}

function run() {
    config

    del_and_add_pf

    sleep 5

    verify_ping

    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
