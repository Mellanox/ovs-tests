#!/bin/bash
#
# Test set e-switch mode in uplink rep mode nic_netdev and disable sriov without
# changing to legacy first.
# Expected not to crash when disabling sriov in the end.
#
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
config_sriov 2
echo "set nic_netdev"
set_uplink_rep_mode_nic_netdev

config
fail_if_err

title "Toggle switchdev for $NIC"
enable_switchdev
# just to make sure we also allocate stuff from ndo open. might find something.
ifconfig $NIC down
ifconfig $NIC up

title "Disable sriov"
echo "disable sriov"
config_sriov 0
config_sriov 0 $NIC2
echo "enable sriov"
config_sriov 2
config_sriov 2 $NIC2
echo "set new_netdev"
set_uplink_rep_mode_new_netdev
set_uplink_rep_mode_new_netdev $NIC2

test_done
