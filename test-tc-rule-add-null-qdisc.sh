#!/bin/bash
#
# This verifies that tc API correctly handles several types of request
# to deleted qdisc.

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

require_interfaces NIC
reset_tc_nic $NIC

title "Verify we cannot add rule if qdisc doesn't exists"
! tc qdisc del dev $NIC ingress
tc filter add dev $NIC protocol 0x800 ingress prio 10 handle 1 flower skip_hw dst_mac e4:11:22:33:44:50 ip_proto udp dst_port 1 src_port 1 action gact drop && err || success
check_num_rules 0 $NIC
check_num_actions 0 gact
tc qdisc add dev $NIC ingress

test_done
