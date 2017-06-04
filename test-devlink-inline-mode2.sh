#!/bin/bash
#
# Test sync between sw and fw
#
#  desc:
#    Verify changing mode switchdev/legacy doesn't reset inline-mode.
#
#  test:
#    - set mode switchdev
#    - set inline_mode to something not the default (not L2/link)
#    - switch to legacy
#    - switch to switchdev
#    - check inline_mode is the same.
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx5

function get_inline_mode() {
    output=`devlink dev eswitch show pci/$PCI`
    echo $output
    mode=`echo $output | grep -o "inline-mode \w*" | awk {'print $2'}`
}

reset_tc_nic $NIC
rep=${NIC}_0
if [ -e /sys/class/net/$rep ]; then
    reset_tc_nic $rep
fi

set -e

switch_mode_switchdev
unbind_vfs

test_mode="transport"
title "test set inline mode $test_mode"
devlink dev eswitch set pci/$PCI inline-mode $test_mode || fail "Failed to set mode $test_mode"
get_inline_mode
test $mode = $test_mode || fail "Expected mode $test_mode"

title "switch mode to legacy and back to switchdev"
switch_mode_legacy
switch_mode_switchdev

title "verify inline_mode is $test_mode"
get_inline_mode
test $mode = $test_mode || fail "Expected mode $test_mode"

title "disable and enable sriov"
set_macs 0
set_macs 2
unbind_vfs

title "verify inline_mode is $test_mode"
get_inline_mode
test $mode = $test_mode || fail "Expected mode $test_mode"

title "reset mode to link"
devlink dev eswitch set pci/$PCI inline-mode link
echo "done"
