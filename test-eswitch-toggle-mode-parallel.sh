#!/bin/bash
#
# Test toggle e-switch modes in parallel user space command
# expected not to crash.
#
# Bug SW #1430455: [OFED 4.4] Server crash during switchdev mode change in parallel
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces NIC NIC2

vfs=2
title "Test toggle switchdev mode in parallel for both ports"
for nic in $NIC $NIC2; do
    echo " - config sriov for $nic"
    config_sriov 0 $nic
    config_sriov $vfs $nic
    unbind_vfs $nic
done

tmp1="/tmp/a$$"
tmp2="/tmp/b$$"

for i in 1 2 3 4 5 ; do
    echo " - config switchdev in paralel"
    rm -fr $tmp1 $tmp2
    enable_switchdev $NIC && touch $tmp1 &
    enable_switchdev $NIC2 && touch $tmp2 &
    #echo switchdev > /sys/class/net/$NIC/compat/devlink/mode &
    #echo switchdev > /sys/class/net/$NIC2/compat/devlink/mode &
    wait
    if [ ! -f $tmp1 ] || [ ! -f $tmp2 ]; then
        err
    fi

    echo " - config legacy in paralel"
    rm -fr $tmp1 $tmp2
    enable_legacy $NIC && touch $tmp1 &
    enable_legacy $NIC2 && touch $tmp2 &
    #echo legacy > /sys/class/net/$NIC/compat/devlink/mode &
    #echo legacy > /sys/class/net/$NIC2/compat/devlink/mode &
    wait
    if [ ! -f $tmp1 ] || [ ! -f $tmp2 ]; then
        err
    fi
done

config_sriov 0 $NIC2
test_done
