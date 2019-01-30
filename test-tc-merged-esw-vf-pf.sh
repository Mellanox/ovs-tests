#!/bin/bash
#
# Test add redirect rule vf on esw0 to uplink on esw1
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test redirect rule from vf on esw0 to vf on esw1"
start_check_syndrome
enable_switchdev_if_no_rep $REP
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2

title "- add redirect rule $REP -> $NIC"
reset_tc_nic $REP
tc_filter add dev $REP protocol ip ingress prio 1 flower skip_sw dst_mac e4:11:22:11:4a:51 action mirred egress redirect dev $NIC

title "- add redirect rule $NIC -> $REP"
reset_tc_nic $NIC
tc_filter add dev $NIC protocol ip ingress prio 1 flower skip_sw dst_mac e4:11:22:11:4a:51 action mirred egress redirect dev $REP

disable_sriov_port2
check_syndrome

test_done
