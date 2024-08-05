#!/bin/bash
#
# Test configuring doca-ovs in legacy mode.
# Not supported but check not crashing.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

# This test only cares to catch a crash and it is expected
# to get error msgs about unsupported mode.
SKIP_OVS_LOG_DUMP=1
add_expected_error_msg "doca_flow_pipe_add_entry"
add_expected_error_msg "Failed to create egress pipe"
add_expected_error_msg "Failed to init DOCA port"
add_expected_error_msg "Failed to set interface"

function cleanup() {
    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    cleanup_test
}

trap cleanup EXIT

function config() {
    config_sriov 0 $NIC
    config_sriov 0 $NIC2
    enable_legacy $NIC
    enable_legacy $NIC2
}

function run() {
    cleanup_test
    config
    start_clean_openvswitch
    ovs_add_bridge br-phy
    ovs_add_dpdk_port br-phy $NIC
    ovs_add_dpdk_port br-phy $NIC2
    ovs-vsctl show
    ovs_clear_bridges
}

run
trap - EXIT
cleanup
test_done
