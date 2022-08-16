#!/bin/bash
#
# Basic VF LAG test with tc shared block
#
# Bug SW #2677225: [CentOS 7.6] driver restart with bonding configured causes system panic

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# [MLNX OFED] BugSW #2854057: [ASAP, OFED 5.5] driver reloading with bonding configured fails due to module mlx5_core is in use
USE_OPENIBD=0

require_module bonding
require_interfaces NIC NIC2

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress &>/dev/null
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function config() {
    echo "- Config"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2
    config_shared_block
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
}

trap cleanup EXIT
cleanup
config
fail_if_err
reload_modules
trap - exit
cleanup
config_sriov
test_done
