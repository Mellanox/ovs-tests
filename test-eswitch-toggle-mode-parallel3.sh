#!/bin/bash
#
# Test toggle e-switch mode and disable sriov in parallel
# expected not to crash.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces NIC

vfs=2
function reconfig() {
    config_sriov $vfs $NIC
    unbind_vfs $NIC
}

title "Test toggle mode and disable sriov in parallel"
# first iteration check we can set switchdev
reconfig
enable_switchdev $NIC

tmp1="/tmp/a$$"
tmp2="/tmp/b$$"

for i in 1 2 3 4 5 ; do
    title " - config in parallel $i"
    rm -fr $tmp1 $tmp2
    # ignore errors in case parallel will give not supported error
    # we just expect not to crash
    __ignore_errors=1
    enable_switchdev $NIC &
    sleep 0.1
    config_sriov 0 $NIC &
    wait
    __ignore_errors=0
    reconfig
done

test_done
