#!/bin/bash
#
# Test add hairpin rule and disable sriov
#
# Bug SW #1513509: Kernel crash when disable SRIOV on Mellanox CX-5 device with hairpin rules
# Bug SW #1732534: [FW] device's health compromised - reached miss count

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function test_hairpin() {
    local nic=$1
    local nic2=$2

    reset_tc $nic

    title "Add hairpin rule $nic to $nic2"
    tc_filter_success add dev $nic protocol ip parent ffff: \
          prio 1 flower skip_sw ip_proto udp \
          action mirred egress redirect dev $nic2

    reset_tc $nic
}

start_check_syndrome

config_sriov 2
enable_legacy
config_sriov 2 $NIC2
enable_legacy $NIC2

test_hairpin $NIC $NIC2

reset_tc $NIC
config_sriov 0 $NIC2

# wait for syndrome. noticed it after 6 seconds.
echo "Wait for syndrome"
sleep 10
check_syndrome
test_done
