#!/bin/bash
#
# Test configuring doca-ovs in switchdev but toggling legacy and back.
#
# [OVS] Bug SW #3993500: openvswitch crash when moving to legacy and back to switchdev while ports added to bridge

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

# Errors are expected so ignore them.
add_expected_error_msg "mlx5_net"

function cleanup() {
    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    cleanup_test
}

trap cleanup EXIT

function run() {
    start_clean_openvswitch
    ovs_add_bridge br-phy
    ovs_add_dpdk_port br-phy $NIC
    ovs_add_dpdk_port br-phy $NIC2
    enable_legacy $NIC
    enable_legacy $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    ovs-vsctl show
    ovs_clear_bridges
}

run
trap - EXIT
cleanup
test_done
