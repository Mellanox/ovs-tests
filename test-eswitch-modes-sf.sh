#!/bin/bash
#
# Check eswitch modes including default (legacy) and the support of SFs.
# Feature Request #2628986: Add Modification E-Switch mode to default (no eswitch) and support it in the devlink query command
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

num=2

function verify_eswitch() {
    local mode=$1

    echo "- Verify eswitch mode is $mode"
    [ `get_eswitch_mode $nic` == $mode ] && success || fail "eswitch mode is not $mode"
}

# The purpose of the reload is to check what eswitch mode will be set after the reload.
title "Reload modules"
unload_modules
load_modules
wait_for_ifaces

verify_eswitch "legacy"

echo "- Create $num SFs - expect to fail"
devlink port add pci/0000:08:00.0 flavour pcisf pfnum 0 sfnum $num 2>&1 | grep -q "Error: mlx5_core: Port add is only supported in eswitch switchdev mode"
[ $? -eq 0 ] && success || fail "Create SFs did not fail as expected"

verify_eswitch "legacy"

title "Change eswitch mode to switchdev"
enable_switchdev && success

echo "- Create $num SFs - expect to pass"
devlink port add pci/0000:08:00.0 flavour pcisf pfnum 0 sfnum $num
[ $? -eq 0 ] && success

verify_eswitch "switchdev"

remove_sfs
test_done
