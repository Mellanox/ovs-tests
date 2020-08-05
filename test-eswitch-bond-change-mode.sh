#!/bin/bash
#
# Test bond0 is still master over two uplinks before sriov and after switchdev mode is set.
# This test is checking the new uplink rep mode where uplink rep is not a new netdev device.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function config() {
    title "disable sriov"
    config_sriov 0
    config_sriov 0 $NIC2
    title "config bonding"
    config_bonding $NIC $NIC2
    fail_if_err
    title "enable sriov"
    config_sriov 2
    config_sriov 2 $NIC2
    title "enable switchdev"
    enable_switchdev
    enable_switchdev $NIC2
}

function cleanup() {
    clear_bonding
    config_sriov 0
    config_sriov 0 $NIC2
}

function verify_bond_master() {
    local nic
    local tmp

    title "verify bond0 is still master"

    for nic in $NIC $NIC2 ; do
        tmp=$(basename `readlink -f /sys/class/net/$nic/master`)
        if [ "$tmp" != "bond0" ]; then
            err "$nic is not slaved to bond0"
        fi
    done
}

trap cleanup EXIT
cleanup
config
verify_bond_master
cleanup
test_done
