#!/bin/bash
#
# Test add redirect rule from VF on esw0 to uplink on esw1
# Expect to fail as we don't support this.
#
# Bug SW #1799666: [Upstream] VF -> UPLINK different eswitch shouldn't be supported but is offloaded.

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test redirect rule from VF on esw0 to uplink on esw1"
start_check_syndrome
enable_switchdev
disable_sriov_port2
enable_sriov_port2
enable_switchdev $NIC2
reset_tc $REP $NIC2

title "- add redirect rule $REP -> $NIC2 - expect to fail as we don't support this"
tc filter add dev $REP protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $NIC2 && err "Expected to fail"

title "- add redirect rule $NIC2 -> $REP - expect to fail as we don't support this"
tc filter add dev $NIC2 protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $REP && err "Expected to fail"

reset_tc $REP
disable_sriov_port2
check_syndrome

test_done
