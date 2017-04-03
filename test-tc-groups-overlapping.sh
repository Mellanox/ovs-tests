#!/bin/bash
#
# Test that verified groups overlapping syndrome
#
# Bug SW #932484: FW error of groups overlapping when scaling up ovs
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test for groups overlapping"
start_check_syndrome
reset_tc_nic $NIC

tc filter add dev $NIC parent ffff: protocol ip pref 8 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol arp pref 1 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 action mirred egress redirect dev $NIC
tc filter del dev $NIC parent ffff: pref 8 handle 0x1 flower
tc filter add dev $NIC parent ffff: protocol ip pref 4 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2229 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip pref 8 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC 

check_syndrome && success || err "Failed"
reset_tc_nic $NIC

echo "done"
