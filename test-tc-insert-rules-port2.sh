#!/bin/bash
#
# Test add drop rule on port 2
#
# Bug SW #1240863: [ECMP] Adding drop rule on port2 cause flow counter doesn't exists syndrome
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
REP=`get_rep 0`
if [ -z "$REP" ]; then
    fail "Missing rep $rep"
fi

function tc_filter() {
    eval2 tc filter $@ || err
}

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
tc_filter add dev $NIC2 protocol ip parent ffff: flower dst_mac e4:11:22:11:4a:51 src_mac e4:11:22:11:4a:50 action drop
reset_tc_nic $NIC2
disable_sriov_port2
check_syndrome

test_done
