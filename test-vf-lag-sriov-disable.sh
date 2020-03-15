#!/bin/bash
#
# Basic VF LAG test with sriov disable
#
# Bug SW #2035950: Removing VFs Hangs
# vfs must be bind for the issue to reproduce, requires at least 2 vfs on each

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function config() {
    echo "- Config"
    config_sriov 0
    config_sriov 0 $NIC2
    config_bonding $NIC $NIC2
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    bind_vfs
    bind_vfs $NIC2
}

function cleanup() {
    clear_bonding
    ifconfig $NIC down
}

function test_disable_sriov() {
    config_sriov 0
    config_sriov 0 $NIC2
}

function do_cmd() {
    title $1
    eval $1
}

trap cleanup EXIT
cleanup
config
fail_if_err
do_cmd test_disable_sriov
cleanup
test_done
