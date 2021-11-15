#!/bin/bash
#
# Testing hairpin by adding rules to TC
# Creating rule from P1 -> V1 and then unbinding V1
#
# Bug SW #2661425: VF unbind fails at reclaiming pages due to hairpin flow

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function test_hairpin_unbind_vf() {
    local nic=$1
    local vf=$2

    title "Reset TC rules on $nic"
    reset_tc $nic

    title "Add hairpin rule $nic to $vf"
    tc_filter_success add dev $nic protocol ip parent ffff: \
          prio 1 flower skip_sw ip_proto udp \
          action mirred egress redirect dev $vf

    title "Show TC rules on $nic"
    tc -s filter show dev $nic ingress

    title "Unbind VFs on $nic"
    unbind_vfs $nic

    title "Show TC rules on $nic"
    tc -s filter show dev $nic ingress

    title "Reset TC rules on $nic"
    reset_tc $nic
}


title "Test hairpin rules in legacy mode"
disable_sriov
enable_sriov

test_hairpin_unbind_vf $NIC $VF

test_done
