#!/bin/bash
#
# Test nic tx progress when switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
config_sriov 2
enable_switchdev

title "Toggle switchdev for $NIC"
ifconfig $NIC 1.1.1.1/24 up

title "Verify traffic with TX counter"

# pre check sysfs. had an issue ifconfig shows no progress and calling ethtool
# cause an update.
sysfs_count1=`cat /sys/class/net/$NIC/statistics/tx_packets`
count1=`get_tx_pkts $NIC`

ip n r 1.1.1.101 dev $NIC lladdr e4:11:22:33:44:55
ping -i 0.01 -c 100 -w 3 -q 1.1.1.101 &>/dev/null

sysfs_count2=`cat /sys/class/net/$NIC/statistics/tx_packets`
count2=`get_tx_pkts $NIC`

((diff=count2-count1))
if [ "$diff" -lt 100 ]; then
    err "Nic $NIC tx is not increasing (diff: $diff)"
fi

((diff=sysfs_count2-sysfs_count1))
if [ "$diff" -lt 100 ]; then
    err "Nic $NIC sysfs tx is not increasing (diff: $diff)"
fi

ip n del 1.1.1.101 dev $NIC
ifconfig $NIC 0
test_done
