#!/bin/bash
#
# Test setting encap through devlink
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function set_encap() {
    title " - test set encap $1"
    set_eswitch_encap $1
}

function test_encap() {
    local val="$1"
    local encap=`get_eswitch_encap`
    test "$encap" = "$val" && success || err "Expected encap '$val' and got '$encap'"
}


set -e

unbind_vfs
switch_mode_switchdev

title "Test toggle encap few times"
for i in `seq 4`; do
    title "Toggle encap mode iter $i"
    set_encap disable
    test_encap none

    set_encap enable
    test_encap basic
done

title "Switch mode to legacy and back to switchdev while encap disabled"
set_encap disable
switch_mode_legacy
switch_mode_switchdev
test_encap none

title "Switch mode to legacy and back to switchdev while encap enabled"
set_encap enable
switch_mode_legacy
switch_mode_switchdev
test_encap basic

if [ "$devlink_compat" = 1 ]; then
    test_done
fi

title "Switch mode with encap"
start_check_syndrome
set_encap disable
test_encap none
switch_mode_legacy
extra_mode="encap enable"
switch_mode_switchdev
test_encap basic
check_syndrome

test_done
