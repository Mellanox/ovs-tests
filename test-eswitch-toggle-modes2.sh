#!/bin/bash
#
# Test toggle e-switch modes in uplink rep mode nic_netdev
# Expected not to crash when disabling sriov in the end.
#
# Issue was when moving back to legacy we failed to destroy resources and disabling sriov caused a crash.
# [  801.190955] mlx5_core 0000:82:00.0: mlx5_destroy_flow_group:2051:(pid 12813): Flow group 95 wasn't destroyed, refcount > 1
# [  801.193872] mlx5_core 0000:82:00.0: mlx5_destroy_flow_table:2040:(pid 12813): Flow table 1048583 wasn't destroyed, refcount > 1
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
config_sriov 2
set_uplink_rep_mode_nic_netdev
fail_if_err

title "Toggle switchdev for $NIC"
for i in 1 2; do
    enable_switchdev
    # down/up interface is important. the crash reproduced with it and didn't
    # without it.
    ifconfig $NIC down
    ifconfig $NIC up
    enable_legacy
done

config_sriov 0
config_sriov 2
set_uplink_rep_mode_new_netdev
config_sriov 0
test_done
