#!/bin/bash
#
# Test add redirect rule from VF on esw0 to uplink on esw1
# Expect to fail as we don't support this.
#
# Bug SW #1799666: [Upstream] VF -> UPLINK different eswitch shouldn't be supported but is offloaded.

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test redirect rule from VF on esw0 to uplink on esw1"
config_sriov 2
enable_switchdev
config_sriov 2 $NIC2
enable_switchdev $NIC2
reset_tc $REP $NIC2

title "add redirect rule $REP -> $NIC2 - expect to fail as we don't support this"
tc filter add dev $REP protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $NIC2 &>/dev/null && err "Expected to fail"

title "add redirect rule $NIC2 -> $REP - expect to fail as we don't support this"
tc filter add dev $NIC2 protocol ip ingress prio 1 flower skip_sw action \
    mirred egress redirect dev $REP &>/dev/null && err "Expected to fail"

reset_tc $REP $NIC2
enable_legacy $NIC2
config_sriov 0 $NIC2
test_done
