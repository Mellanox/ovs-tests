#!/bin/bash
#
# Test vf lag when changing eswitch mode without sriov
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function config() {
    title "- config"
    disable_sriov

    # newer kernels allow to change eswitch mode without enabling sriov. seems to break activating
    # lag. WA config and disable sriov again.
    enable_legacy $NIC2

    wait_for_ifaces
    config_bonding $NIC $NIC2
    fail_if_err
    reset_tc $NIC $NIC2
    fail_if_err
}

function cleanup() {
    clear_bonding
    disable_sriov
}

trap cleanup EXIT
cleanup
config
trap - EXIT
cleanup
test_done
