#!/bin/bash
#
# Test toggle e-switch modes in parallel user space command
# expected not to crash.
#
# Bug SW #1430455: [OFED 4.4] Server crash during switchdev mode change in parallel
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

vfs=2
title "Test toggle switchdev mode in parallel for both ports"
for nic in $NIC $NIC2; do
    echo " - config sriov for $nic"
    config_sriov 0 $nic
    config_sriov $vfs $nic
    unbind_vfs $nic
done

for i in 1 2 3 4 5 ; do
    echo " - config switchdev in paralel"
    enable_switchdev $NIC &
    enable_switchdev $NIC2 &
    #echo switchdev > /sys/class/net/$NIC/compat/devlink/mode &
    #echo switchdev > /sys/class/net/$NIC2/compat/devlink/mode &
    wait
    echo " - config legacy in paralel"
    enable_legacy $NIC &
    enable_legacy $NIC2 &
    #echo legacy > /sys/class/net/$NIC/compat/devlink/mode &
    #echo legacy > /sys/class/net/$NIC2/compat/devlink/mode &
    wait
done

config_sriov 0 $NIC2
test_done
