#!/bin/bash
#
# Test setting encap through devlink
# Requires CX-4 LX (MT4117)
#

NIC=${1:-ens5f0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx5

function get_encap() {
    if [ "$devlink_compat" = 1 ]; then
        output=`cat /sys/kernel/debug/mlx5/$PCI/compat/encap`
        if [ "$output" = "none" ]; then
            encap="disable"
        elif [ "$output" = "basic" ]; then
            encap="enable"
        else
            fail "Failed to get encap"
	fi
    else
        output=`devlink dev eswitch show pci/$PCI`
        encap=`echo $output | grep -o "encap \w*" | awk {'print $2'}`
    fi
    
    echo $output
}

function set_encap() {
    local val="$1"
    title " - test set encap $val"

    if [ "$devlink_compat" = 1 ]; then
	if [ "$val" = "disable" ]; then
            val="none"
        elif [ "$val" = "enable" ]; then
            val="basic"
        else
            fail "Failed to set encap"
        fi
        echo $val > /sys/kernel/debug/mlx5/$PCI/compat/encap && success || fail "Failed to set encap"
    else
        devlink dev eswitch set pci/$PCI encap $val && success || fail "Failed to set encap"
    fi
}

function test_encap() {
    local val="$1"
    title " - verify encap is $val"
    get_encap
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
