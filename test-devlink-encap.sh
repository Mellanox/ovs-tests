#!/bin/bash
#
# Test setting encap through devlink
# Requires CX-4 LX (MT4117)
#

NIC=${1:-ens5f0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx5

function set_encap() {
    title " - test set encap $1"
    set_eswitch_encap $1
}

function test_encap() {
    local val="$1"
    title " - verify encap is $val"
    local encap=`get_eswitch_encap`
    test "$encap" = "$val" && success || fail "Expected encap '$val' and got '$encap'"
}


set -e

unbind_vfs
switch_mode_switchdev

title "Test toggle encap few times"
for i in `seq 4`; do
    set_encap disable
    test_encap disable

    set_encap enable
    test_encap enable
done

title "Switch mode to legacy and back to switchdev while encap disabled"
set_encap disable
switch_mode_legacy
switch_mode_switchdev
test_encap disable

title "Switch mode to legacy and back to switchdev while encap enabled"
set_encap enable
switch_mode_legacy
switch_mode_switchdev
test_encap enable

title "switch mode with encap"
start_check_syndrome
set_encap disable
test_encap disable
switch_mode_legacy
if [ "$devlink_compat" = 1 ]; then
    set_encap enable
else
    extra_mode="encap enable"
fi
switch_mode_switchdev
test_encap enable
check_syndrome

test_done
