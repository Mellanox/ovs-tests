#!/bin/bash
#
# Test setting encap through devlink
# Requires CX-4 LX (MT4117)
#


NIC=${1:-ens5f0}
PCI=$(basename `readlink /sys/class/net/$NIC/device`)
echo "NIC PCI $PCI"

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function get_encap() {
    output=`devlink dev eswitch show pci/$PCI`
    echo $output
    encap=`echo $output | grep -o "encap \w*" | awk {'print $2'}`
}

function set_encap() {
    local val="$1"
    title " - test set encap $val"
    devlink dev eswitch set pci/$PCI encap $val && success || fail "Failed to set encap"
}

function test_encap() {
    local val="$1"
    title " - verify encap is $val"
    get_encap
    test "$encap" = "$val" && success || fail "Expected encap '$val' and got '$encap'"
}


reset_tc_nic $NIC
rep=${NIC}_0
if [ -e /sys/class/net/$rep ]; then
    reset_tc_nic $rep
fi

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
switch_mode_switchdev "encap enable"
test_encap enable
check_syndrome

test_done
