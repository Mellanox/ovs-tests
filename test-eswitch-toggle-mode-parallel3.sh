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
reconfig

tmp1="/tmp/a$$"
tmp2="/tmp/b$$"

for i in 1 2 3 4 5 ; do
    title " - config in parallel $i"
    rm -fr $tmp1 $tmp2
    enable_switchdev $NIC && touch $tmp1 &
    sleep 0.1
    config_sriov 0 $NIC && touch $tmp2 &
    wait
    if [ ! -f $tmp1 ] || [ ! -f $tmp2 ]; then
        err
    fi
    reconfig
done

test_done
