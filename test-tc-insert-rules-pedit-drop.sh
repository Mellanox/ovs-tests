#!/bin/bash
#
# Bug SW #2916155: [Upstream][K8s] Syndrome 0x8708c3 over VST VLan
#
# kernel: mlx5_core 0000:08:00.0: mlx5_cmd_check:777:(pid 101477): SET_FLOW_TABLE_ENTRY(0x936) op_mod(0x0) failed, status bad parameter(0x3), syndrome (0x8708c3)

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4

function tc_filter_fail() {
    eval tc -s filter $@ && err "Expected to fail adding rule"
}

function test_basic_header_rewrite() {
    title "Add basic pedit rule on representor with drop"
    reset_tc $REP
    tc_filter_fail add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw ip_proto icmp \
        action pedit ex munge eth dst set 20:22:33:44:55:66 \
        pipe action drop
    reset_tc $REP
}

config_sriov 2
enable_switchdev

test_basic_header_rewrite

test_done
