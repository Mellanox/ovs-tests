#!/bin/bash
#
# Check eswitch modes including default (legacy) and the support of VFs.
# Feature Request #2628986: Add Modification E-Switch mode to default (no eswitch) and support it in the devlink query command
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function verify_eswitch() {
    local mode=$1

    echo "- Verify eswitch mode is $mode"
    [ `get_eswitch_mode $nic` == $mode ] && success || fail "eswitch mode is not $mode"
}

function verify_eswitch_after_enable_disable_sriov(){
    local mode=$1

    echo "- Enable sriov"
    config_sriov 2 $NIC && success
    verify_eswitch $mode

    echo "- Disable sriov"
    config_sriov 0 $NIC && success
    verify_eswitch $mode
}

# The purpose of the reload is to check what eswitch mode will be set after the reload.
title "Reload modules"
unload_modules
load_modules
wait_for_ifaces

verify_eswitch "legacy"
verify_eswitch_after_enable_disable_sriov "legacy"

title "Change eswitch mode to switchdev"
enable_switchdev && success

verify_eswitch_after_enable_disable_sriov "switchdev"

test_done
