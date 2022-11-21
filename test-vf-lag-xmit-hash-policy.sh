#!/bin/bash
#
# Check configuring bond with different xmit hash policies.
# Bond modes are balance-xor and 802.3ad.
#
# Bug SW #2780336: Kernel panic and call trace appears in mlx5_del_flow_rules when creating vf-lag with xmit hash policy layer2+3
# Require LAG_RESOURCE_ALLOCATION to be enabled.
# Newer FW versions do not require enabling LAG_RESOURCE_ALLOCATION anymore to move to hash mode.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
require_module bonding

function config() {
    config_sriov 2
    config_sriov 2 $NIC2
    set_lag_port_select_mode "hash"
    enable_switchdev
    enable_switchdev $NIC2
}

function cleanup() {
    clear_bonding
    restore_lag_port_select_mode
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

function check_bond_xmit_hash_policy() {
    for mode in balance-xor 802.3ad; do
        for policy in layer2 layer2+3 layer3+4 encap2+3 encap3+4; do
            title "Checking bond mode $mode xmit hash policy $policy"
            config_bonding $NIC $NIC2 $mode $policy
            dmesg | tail -n20 | grep -q "mode:hash"
            if [ $? -ne 0 ]; then
                err "Expected vf lag mode hash"
                return
            fi
            clear_bonding
        done
    done
}

trap cleanup EXIT
is_not_simx && fw_ver_lt 33 1048 && set_lag_resource_allocation 1

config
check_bond_xmit_hash_policy

is_not_simx && fw_ver_lt 33 1048 && set_lag_resource_allocation 0
trap - EXIT
cleanup
test_done
