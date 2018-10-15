#!/bin/bash
#
# Test add redirect rule vf on esw0 to vf on esw1
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function disable_sriov_port2() {
    echo "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov_port2() {
    echo "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}


title "Test redirect rule from vf on esw0 to vf on esw1"
start_check_syndrome
enable_switchdev_if_no_rep $REP
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2
REP2=`get_rep 0 $NIC2`

title "- add redirect rule $REP -> $REP2"
reset_tc_nic $REP
tc_filter add dev $REP protocol ip ingress flower skip_sw dst_mac e4:11:22:11:4a:51 action mirred egress redirect dev $REP2

title "- add redirect rule $REP2 -> $REP"
reset_tc_nic $REP2
tc_filter add dev $REP2 protocol ip ingress flower skip_sw dst_mac e4:11:22:11:4a:51 action mirred egress redirect dev $REP

disable_sriov_port2
check_syndrome

test_done
