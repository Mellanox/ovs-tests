#!/bin/bash
#
# Test configuring doca-ovs in legacy mode.
# Not supported but check not crashing.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

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
