#!/bin/bash
#
# Test add hairpin rule and disable sriov
#
# Bug SW #1513509: Kernel crash when disable SRIOV on Mellanox CX-5 device with hairpin rules

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function tc_filter() {
    eval2 tc filter $@ && success
}

function test_hairpin() {
    local nic=$1
    local nic2=$2

    reset_tc $nic

    title "Add hairpin rule $nic to $nic2"
    tc_filter add dev $nic protocol ip parent ffff: \
          prio 1 flower skip_sw ip_proto udp \
          action mirred egress redirect dev $nic2

    reset_tc $nic
}

start_check_syndrome

enable_legacy

test_hairpin $NIC $NIC2

config_sriov 0
config_sriov 2

check_syndrome
test_done
