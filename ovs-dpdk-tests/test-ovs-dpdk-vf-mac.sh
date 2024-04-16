#!/bin/bash
#
# Test configuring doca-ovs dpdk-vf-mac
# Setting dpdk vf mac on PF is not supported and catching memory leak.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

function cleanup() {
    cleanup_test
}

trap cleanup EXIT

function config() {
    config_sriov 2 $NIC
    enable_switchdev
}

function run() {
    cleanup_test
    config
    start_clean_openvswitch
    ovs_add_bridge br-phy
    ovs_add_dpdk_port br-phy $NIC
    ovs-vsctl set Interface $NIC options:dpdk-vf-mac=00:11:22:33:44:55
    ovs-vsctl show
    ovs_clear_bridges
}

run
trap - EXIT
cleanup
test_done
