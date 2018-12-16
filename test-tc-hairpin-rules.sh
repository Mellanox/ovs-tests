#!/bin/bash
#
# Testing hairpin by adding rules to TC
# Creating rule from P1 --> P2 and from P2 --> P1
# on the same NIC in legacy mode
#

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
          flower prio 1 skip_sw ip_proto udp \
          action mirred egress redirect dev $nic2

    reset_tc $nic
}

start_check_syndrome

enable_legacy

test_hairpin $NIC $NIC2
test_hairpin $NIC2 $NIC

check_syndrome
test_done