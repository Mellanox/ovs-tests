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
REP=${NIC}_0

my_dir="$(dirname "$0")"
. $my_dir/common.sh

relevant_for_cx4

reset_tc $NIC
if [ -e /sys/class/net/$REP ]; then
    reset_tc $REP
fi

set -e

switch_mode_switchdev
unbind_vfs

test_mode="transport"
title "test set inline mode $test_mode"
set_eswitch_inline_mode $test_mode || fail "Failed to set mode $test_mode"
mode=`get_eswitch_inline_mode`
test $mode = $test_mode || fail "Expected mode $test_mode but got $mode"

title "switch mode to legacy and back to switchdev"
switch_mode_legacy
switch_mode_switchdev

title "verify inline_mode is $test_mode"
mode=`get_eswitch_inline_mode`
test $mode = $test_mode || fail "Expected mode $test_mode but got $mode"

title "disable and enable sriov"
set_macs 0
set_macs 2
unbind_vfs

title "verify inline_mode is $test_mode"
mode=`get_eswitch_inline_mode`
test $mode = $test_mode || fail "Expected mode $test_mode but got $mode"

title "reset mode to transport"
set_eswitch_inline_mode transport
test_done
