#!/bin/bash
#
# Test add hairpin rule and disable sriov
#
# Bug SW #1513509: Kernel crash when disable SRIOV on Mellanox CX-5 device with hairpin rules
# Bug SW #1732534: [FW] device's health compromised - reached miss count

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function add_hairpin_rule() {
    local nic=$1
    local nic2=$2

    title "Add hairpin rule $nic to $nic2"
    tc_filter_success add dev $nic protocol ip parent ffff: \
          prio 1 flower skip_sw ip_proto udp \
          action mirred egress redirect dev $nic2
}

disable_sriov
enable_sriov
reset_tc $NIC $NIC2
add_hairpin_rule $NIC2 $NIC
config_sriov 0 $NIC2

# wait for syndrome. noticed it after 6 seconds.
echo "Wait for syndrome"
sleep 10
reset_tc $NIC $NIC2
test_done
