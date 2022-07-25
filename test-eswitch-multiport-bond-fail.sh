#!/bin/bash
#
# Set lag_port_select_mode to multiport_esw and check fail to attach slave to a bond.
# Driver in multiport_esw mode doesn't support bonding.
# Bug SW #2851706: [ASAP, OFED 5.5, multiport_esw] multiport_esw should block bond device enslaving
# Require LAG_RESOURCE_ALLOCATION to be enabled.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
require_module bonding

function config() {
    config_sriov 2
    config_sriov 2 $NIC2
    set_lag_port_select_mode "multiport_esw"
    enable_switchdev
    enable_switchdev $NIC2
}

function cleanup() {
    clear_bonding
    set_lag_port_select_mode "queue_affinity"
    config_sriov 2
    config_sriov 0 $NIC2
    enable_switchdev
}

function check_bond_fail() {
    title "Trying to attach slaves to a bond"
    __ignore_errors=1
    __config_bonding $NIC $NIC2
    local rc=$?
    __ignore_errors=0

    if [ "$rc" != "0" ]; then
        success
    else
        err "Expected to fail"
    fi
}

trap cleanup EXIT

clear_bonding
set_lag_resource_allocation 1
config
check_bond_fail
set_lag_resource_allocation 0
trap - EXIT
cleanup
test_done
