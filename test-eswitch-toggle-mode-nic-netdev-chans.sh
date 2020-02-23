#!/bin/bash
#
# Test toggle e-switch modes in uplink rep mode nic_netdev and toggle link
# down/up in background.
# Expected not to crash adding sqs rules because channels not fully open.
# Bug SW #2048014: [ASAP, centos 7.2(default kernel), OFED 5.0] kernel panic after change mode to switchdev over nic_netdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
config_sriov 2
set_uplink_rep_mode_nic_netdev
fail_if_err

function toggle_ports() {
    echo "toggle nic down/up"
    for i in `seq 20`; do
        ifconfig $NIC down
        ifconfig $NIC up
    done
}

title "Toggle switchdev for $NIC"
for i in `seq 5`; do
    title "Iter $i"
    toggle_ports &
    enable_switchdev
    enable_legacy
    wait
done

config_sriov 0
config_sriov 2
set_uplink_rep_mode_new_netdev
config_sriov 0
test_done
