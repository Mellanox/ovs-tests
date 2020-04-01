#!/bin/bash
#
# Test verify insertion rule with following hw stats:
# 1. disabled (should fail)
# 2. immediate (should fail)
# 3. delayed
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP

function tc_wrapper() {
    local command_2_call=$1
    local stats=$2

    $command_2_call add dev $REP ingress proto ip handle 1 pref 1 \
        flower skip_sw \
            dst_ip 7.7.7.7 \
            action drop \
            hw_stats $stats
}

function test_unsupported_hw_stats() {

    title "Test adding unsupported hw stats"
    for stats_type in disabled immediate
    do
        echo "* adding rule with $stats_type"
        tc_wrapper "tc filter" $stats_type && \
            err "Expected to fail with $stats_type stats" || success
        reset_tc $REP
    done
}

function test_supported_hw_stats() {

    title "Test adding supported hw stats"
    for stats_type in delayed
    do
        echo "* adding rule with $stats_type"
        tc_wrapper tc_filter_success $stats_type

        [ $? -ne 0  ] && continue
        echo "* check installed rule"
        local output=$(tc -s filter show dev $REP ingress)
        echo $output
        echo $output | grep -q $stats_type && \
            success || error "No $stats_type stats found"
        reset_tc $REP
    done
}

reset_tc $REP
test_unsupported_hw_stats
test_supported_hw_stats

test_done
