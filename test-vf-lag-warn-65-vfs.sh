#!/bin/bash
#
# Feature #2101052: Add message to Linux dmesg & logging when VF-LAG fails to start
# Note: the test configs 65 vfs.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
require_mlxconfig
require_interfaces NIC NIC2

function set_num_of_vfs() {
    fw_config NUM_OF_VFS=$1
}

function config() {
    echo "- Config"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2 $REP
}

function cleanup() {
    rmmod bonding
}

function test_bond_mode() {
    local ret1
    local ret2

    ip link add name bond1 type bond mode $1 miimon 100 || fail "Failed to create bond interface"

    ip link set dev $NIC down
    ip link set dev $NIC2 down
    ret1=$(ip link set dev $NIC master bond1 2>&1 >/dev/null)
    ret2=$(ip link set dev $NIC2 master bond1 2>&1 >/dev/null)
    ip link set dev bond1 up
    ip link set dev $NIC up
    ip link set dev $NIC2 up

    sleep 2

    ip link set dev $NIC nomaster &>/dev/null
    ip link set dev $NIC2 nomaster &>/dev/null
    ip link del name bond1 &>/dev/null

    if [[ $ret1 != "" || $ret2 != $warning ]]; then
        err "unexpected warning returned."
    elif is_bonded ; then
        err "VF LAG is activated."
    else
        success
    fi
}

trap cleanup EXIT
start_check_syndrome

num_vfs=`fw_query_val NUM_OF_VFS`

disable_sriov
set_num_of_vfs 65
fw_reset
wait_for_ifaces
config

warning="Warning: mlx5_core: Can't activate LAG offload, PF is configured with more than 64 VFs."
title "Test active-backup mode with 65 VFs configured"
test_bond_mode active-backup

disable_sriov
set_num_of_vfs $num_vfs
fw_reset
wait_for_ifaces
config

check_syndrome
fail_if_err
test_done
