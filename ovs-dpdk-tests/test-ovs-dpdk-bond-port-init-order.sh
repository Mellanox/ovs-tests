#!/bin/bash
#
# Test adding bond0 port after reps
#
# [OVS] Bug SW #3845886: [Ovs-DOCA] ovs crashes in bond configurations

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common-sf.sh

enable_switchdev

function cleanup() {
    clean_vf_lag
    cleanup_test
}

trap cleanup EXIT

function clean_vf_lag() {
    # must unbind vfs to create/destroy lag
    unbind_vfs $NIC
    unbind_vfs $NIC2
    clear_bonding
}

function config_vf_lag() {
    local mode=${1:-"802.3ad"}

    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2 $mode || fail
    bind_vfs $NIC
    bind_vfs $NIC2
}

function config() {
    config_vf_lag
}

function run() {
    cleanup
    config
    start_clean_openvswitch
    ovs_add_bridge br-phy
    # order is important. checking reps first before pf.
    local pf1vf0=`get_rep 0 $NIC2`
    __ovs_add_port br-phy $pf1vf0 dpdk
    __ovs_add_port br-phy $REP dpdk
    __ovs_add_port br-phy bond0 dpdk
    ovs-vsctl show
    # ovs could return success on adding the bond port but it still could be in error state.
    ovs-vsctl show | grep -q "error" && err "Some ports in error state."
    restart_openvswitch
    ovs_clear_bridges
}

run
trap - EXIT
cleanup
test_done
