#!/bin/bash
#
# Test toggle e-switch modes
# - sriov on/off
# - switchdev/legacy
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Toggle sriov"
for nic in $NIC $NIC2; do
    config_sriov 0 $nic
    config_sriov 2 $nic
    enable_switchdev $nic
    enable_legacy $nic
    config_sriov 0 $nic
    config_sriov 2 $nic
done

config_sriov 0 $NIC2
test_done
