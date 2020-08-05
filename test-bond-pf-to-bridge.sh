#!/bin/bash
#
# Test adding PFs to bond0 in SRIOV mode and add bond0 to a bridge.
#
# BugSW #2239358: can't add bond0 to bridge br0: No data available
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
require_interfaces NIC NIC2

function config() {
    title "disable sriov"
    config_sriov 0
    config_sriov 0 $NIC2
    title "enable sriov"
    config_sriov 2
    config_sriov 2 $NIC2
    title "config bonding"
    __config_bonding $NIC $NIC2
    fail_if_err
}

function cleanup() {
    brctl delbr brrr9 &>/dev/null
    clear_bonding
    config_sriov 0
    config_sriov 0 $NIC2
}

function add_bond_to_bridge() {
    title "add bridge and attach bond0"
    brctl addbr brrr9 || fail "Failed adding bridge"
    brctl addif brrr9 bond0 || fail "Failed adding bond0 to bridge"
}

trap cleanup EXIT
cleanup
config
add_bond_to_bridge
title "cleanup"
cleanup
test_done
