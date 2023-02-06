#!/bin/bash
#
# Test add redirect rule from uplink on esw0 to uplink on esw1
# Expect to fail as we don't support this.
#
# BugSW #2053699: FW accepts unsupported FTE to forward packets from uplink1 to uplink2

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function run() {
    config_sriov 2
    enable_switchdev
    config_sriov 2 $NIC2
    enable_switchdev $NIC2

    title "Test redirect rule from uplink on esw0 $NIC to uplink on esw1 $NIC2 - expected to fail"
    reset_tc $NIC
    tc filter add dev $NIC protocol ip ingress prio 1 flower skip_sw action \
        mirred egress redirect dev $NIC2 &>/dev/null
    [ $? -ne 0 ] && success && return
    err "Expected to fail"
}

run
reset_tc $NIC
config_sriov 0 $NIC2
test_done
