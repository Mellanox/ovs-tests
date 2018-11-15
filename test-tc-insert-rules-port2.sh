#!/bin/bash
#
# Test add drop rule on port 2
#
# Bug SW #1240863: [ECMP] Adding drop rule on port2 cause flow counter doesn't exists syndrome
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
require_interfaces NIC NIC2

function disable_sriov_port2() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov_port2() {
    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}


title "Test drop rule on port2"
start_check_syndrome
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2
reset_tc_nic $NIC2
title "- Add drop rule"
tc_filter add dev $NIC2 protocol ip parent ffff: flower skip_sw dst_mac e4:11:22:11:4a:51 src_mac e4:11:22:11:4a:50 action drop
reset_tc_nic $NIC2
disable_sriov_port2
check_syndrome

test_done
