#!/bin/bash
#
# Test toggle e-switch modes
# - sriov on/off
# - switchdev/legacy
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


for nic in $NIC $NIC2; do
    title "Toggle sriov/switchdev for $nic"
    for i in 1 2; do
        config_sriov 0 $nic
        config_sriov 2 $nic
    done
    for i in 1 2; do
        enable_switchdev $nic
        enable_legacy $nic
    done
    for i in 1 2; do
        config_sriov 0 $nic
        config_sriov 2 $nic
    done
done

config_sriov 0 $NIC2
test_done
