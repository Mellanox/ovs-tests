#!/bin/bash
#
# Test WA for "toggle e-switch modes while adding/deleting net namespace" Issue
#
# Bug SW #2938383: [K8S UPSTREAM BF2] DPU can't switch to switchdev mode
#
# Same as test-eswitch-toggle-mode-ns.sh but unload mlx5_ib first to avoid catching issue
# from that module and catch issue in mlx5_core.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function toggle_ns() {
    local ns
    for ns in ns0 ns1 ns2; do
        ip netns add $ns
    done
    sleep 1
    for ns in ns0 ns1 ns2; do
        ip netns del $ns
    done
}

function start1() {
    local i

    title "Toggle switchdev for $NIC"
    toggle_ns &
    for i in 1 2; do
        rmmod mlx5_ib
        enable_switchdev $NIC
        enable_legacy $NIC
    done
    echo wait
    wait
}

config_sriov 2
enable_legacy
start1

test_done
