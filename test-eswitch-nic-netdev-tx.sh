#!/bin/bash
#
# Test nic tx works when switchdev mode in nic_netdev mode
# We got into an issue where we need to down/up the nic for it to work again.
# Bug SW #1953215: No traffic on uplink after moving it switchdev when the uplink mode is nic_netdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
config_sriov 2
set_uplink_rep_mode_nic_netdev
fail_if_err

title "Toggle switchdev for $NIC"
ifconfig $NIC 1.1.1.1/24 up
enable_switchdev

title "Verify traffic with TX counter"
count1=`get_tx_pkts $NIC`
ip n r 1.1.1.101 dev $NIC lladdr e4:11:22:33:44:55
ping -i 0.01 -c 100 -w 3 -q 1.1.1.101 &>/dev/null
count2=`get_tx_pkts $NIC`
((diff=count2-count1))
if [ "$diff" -lt 100 ]; then
    err "Nic $NIC tx is not increasing (diff: $diff)"
fi

ip n del 1.1.1.101 dev $NIC
enable_legacy
ifconfig $NIC 0
config_sriov 0
config_sriov 2
set_uplink_rep_mode_new_netdev
config_sriov 0
test_done
