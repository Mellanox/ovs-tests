#!/bin/bash
#
# Test configuring doca-ovs in switchdev but toggling legacy and back.
# Errors are expected but not to crash.
#
# [OVS] Bug SW #3993500: openvswitch crash when moving to legacy and back to switchdev while ports added to bridge

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

# Errors are expected so ignore them as long as not related to the crash.
add_expected_error_msg "mlx5_net"
add_expected_error_msg "Failed to load driver mlx5_eth"
add_expected_error_msg "EAL: Failed to attach device on primary"

function cleanup() {
    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    cleanup_test
}

trap cleanup EXIT

function run() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    config_remote_nic
    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF1 $LOCAL_IP
    ovs_add_dpdk_port br-phy $NIC2
    # do some traffic. reproduced different crash when traffic was done and
    # updated ports while rules exists.
    verify_ping $REMOTE_IP ns0
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
