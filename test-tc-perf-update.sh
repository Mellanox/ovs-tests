#!/bin/bash
#
# This test measures performance of tc rules update. It inserts/deletes
# arbitrary number (L2 and 5-tuple) of rules in single instance or multi
# instance tc mode. Baseline time values should be set in per-setup
# configuration file.
#
# IGNORE_FROM_TEST_ALL
#

total=${1:-100000}
num_tc=${2:-1}
skip=$3
let per_file=$total/$num_tc

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

require_interfaces NIC
reset_tc_nic $NIC

function run_multi_tc() {
    local file_name=$1
    local num_rules=$2
    local baseline=$3

    # Spawn tc instance per batch file and measure execution time. Save 'time' output to out
    out=$( { time -p ls ${TC_OUT}/${file_name}.* | xargs -n 1 -P 100 tc -b; } 2>&1 1>/dev/null )
    # Extract 'real' time
    [[ $out =~ [^0-9]*([0-9]+\.[0-9]+) ]]
    real_time="${BASH_REMATCH[1]}"
    # Calculate absolute difference between baseline and this test run (per cent).
    read difference <<< $(awk -v t1="$real_time" -v t2="$baseline" 'BEGIN{diff=(t2-t1)/t1 * 100;abs=diff<0?-diff:diff; printf "%.0f", abs}')

    if [[ -z $baseline ]]; then
        err "Please set baseline in config file. Command executed in $real_time sec"
    elif ((difference>10)); then
        err "Command execution took $real_time sec, baseline is $baseline sec ($difference % difference)"
    else
        success "Command execution took $real_time sec, baseline is $baseline sec ($difference % difference)"
    fi

    check_num_rules $num_rules $NIC
}

function perf_test() {
    local rules_per_file=$1
    local classifier=$2
    local baseline_ins=$3
    local baseline_del=$4

    tc_batch 0 "dev $NIC" $total $rules_per_file "$classifier"
    reset_tc_nic $NIC $classifier

    echo "Insert rules"
    run_multi_tc add $total $baseline_ins

    echo "Delete rules"
    run_multi_tc del 0 $baseline_del
}

title "Test $num_tc tc instance(s) with $total L2 rules"
perf_test $per_file "" $PERF_TC_L2_INSERT $PERF_TC_L2_DELETE

title "Test $num_tc tc instance(s) with $total L2+5tuple rules"
perf_test $per_file "src_ip 192.168.111.1 dst_ip 192.168.111.2 ip_proto udp dst_port 1 src_port 1" $PERF_TC_5T_INSERT $PERF_TC_5T_DELETE

test_done
