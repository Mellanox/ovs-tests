#!/bin/bash
#
# Bug SW #3240995: [Upstream] Fail to config sriov on port2 if mode is switchdev first

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev $NIC
enable_switchdev $NIC2

function start1() {
    title "Toggle legacy for $NIC"
    rmmod mlx5_ib # important for repro.
    enable_legacy $NIC

    title "Reconfig sriov $NIC2"
    config_sriov 0 $NIC2
    config_sriov 2 $NIC2
}

function cleanup() {
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

trap cleanup EXIT

start1

cleanup
trap - EXIT
test_done
