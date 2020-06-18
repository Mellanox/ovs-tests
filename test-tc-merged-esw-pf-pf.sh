#!/bin/bash
#
# Test add redirect rule from uplink on esw0 to uplink on esw1
# Expect to fail as we don't support this.
#
# BugSW #2053699: FW accepts unsupported FTE to forward packets from uplink1 to uplink2

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test redirect rule from uplink on esw0 to uplink on esw1"
start_check_syndrome
enable_switchdev
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2

title "- add redirect rule $NIC -> $NIC2 - expect to fail as we don't support this"
reset_tc $NIC
tc filter add dev $NIC protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $NIC2 && err "Expected to fail"
reset_tc $NIC

disable_sriov_port2
check_syndrome

test_done
