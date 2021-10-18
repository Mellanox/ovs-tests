#!/bin/bash
#
# Check configuring bond with different xmit hash policies.
# Bond modes are balance-xor and 802.3ad.
#
# Bug SW #2780336: Kernel panic and call trace appears in mlx5_del_flow_rules when creating vf-lag with xmit hash policy layer2+3
# Require LAG_RESOURCE_ALLOCATION to be enabled.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function set_lag_resource_allocation() {
    local mode=$1
    title "lag_resource_allocation value to $mode"
    fw_config LAG_RESOURCE_ALLOCATION=$mode || fail "Cannot set lag resource allocation to $mode"
    fw_reset
}

function set_lag_port_select_mode() {
    if ! is_ofed ; then
        return
    fi
    local mode=$1
    enable_legacy &>/dev/null
    enable_legacy $NIC2 &>/dev/null
    echo $mode > /sys/class/net/$NIC/compat/devlink/lag_port_select_mode || fail "failed to set lag_port_select_mode to $mode"
    echo $mode > /sys/class/net/$NIC2/compat/devlink/lag_port_select_mode || fail "failed to set lag_port_select_mode to $mode"
}

function config() {
    config_sriov 2
    config_sriov 2 $NIC2
    set_lag_port_select_mode "hash"
    enable_switchdev
    enable_switchdev $NIC2
}

function cleanup() {
    clear_bonding
    set_lag_port_select_mode "queue_affinity"
    config_sriov 2 &>/dev/null
    config_sriov 0 $NIC2 &>/dev/null
    enable_switchdev &>/dev/null
}

function check_bond_xmit_hash_policy() {
    for mode in balance-xor 802.3ad; do
        for policy in layer2 layer2+3 layer3+4 encap2+3 encap3+4; do
            title "Checking bond mode $mode xmit hash policy $policy"
            config_bonding $NIC $NIC2 $mode $policy
            clear_bonding
            dmesg | tail -n20 | grep -q "mode:hash"
            if [ $? -ne 0 ]; then
                err "Expected vf lag mode hash"
                return
            fi
        done
    done
}

trap cleanup EXIT
start_check_syndrome
clear_bonding
set_lag_resource_allocation 1
config
check_bond_xmit_hash_policy
set_lag_resource_allocation 0
check_syndrome
test_done
