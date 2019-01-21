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

    # Spawn tc instance per batch file and measure execution time. Save 'time' output to out
    out=$( { time -p ls ${TC_OUT}/${file_name}.* | xargs -n 1 -P 100 tc -b; } 2>&1 1>/dev/null )
    # Extract 'real' time
    [[ $out =~ [^0-9]*([0-9]+\.[0-9]+) ]]
    real_time="${BASH_REMATCH[1]}"

    echo $real_time
}

function calc_abs_diff_per_cent() {
    local baseline_res=$1
    local new_res=$2

    # Calculate absolute difference between baseline time and this test run (per cent).
    read difference <<< $(awk -v v1="$new_res" -v v2="$baseline_res" 'BEGIN{diff=(v2-v1)/v1 * 100;abs=diff<0?-diff:diff; printf "%.0f", abs}')

    echo $difference
}

function run_benchmark_time() {
    local file_name=$1
    local num_rules=$2
    local baseline_time=$3

    real_time=$(run_multi_tc $file_name)
    difference_time=$(calc_abs_diff_per_cent $baseline_time $real_time)

    if [[ -z $baseline_time ]]; then
        err "Please set baseline time in config file. Command executed in $real_time sec"
    elif ((difference_time>10)); then
        err "Command execution took $real_time sec, baseline time is $baseline_time sec ($difference_time % difference)"
    else
        success "Command execution took $real_time sec, baseline time is $baseline_time sec ($difference_time % difference)"
    fi

    check_num_rules $num_rules $NIC
}

function calc_used_mem() {
    vmstat -s | grep -i "used memory" | awk {'print $1'}
}

function run_benchmark_time_mem() {
    local file_name=$1
    local num_rules=$2
    local baseline_time=$3
    local baseline_mem=$4

    local used_mem_start=$(calc_used_mem)

    real_time=$(run_multi_tc $file_name)
    difference_time=$(calc_abs_diff_per_cent $baseline_time $real_time)

    local used_mem_end=$(calc_used_mem)
    (( total_mem = used_mem_end - used_mem_start ))
    local difference_mem=$(calc_abs_diff_per_cent $baseline_mem $total_mem)

    if [[ -z $baseline_time ]]; then
        err "Please set baseline time in config file. Command executed in $real_time sec, used $total_mem K memory"
    elif [[ -z $baseline_mem ]]; then
        err "Please set baseline memory consumption in config file. Command used $total_mem K memory"
    elif ((difference_time>10)); then
        err "Command execution took $real_time sec, baseline time is $baseline_time sec ($difference_time % difference)"
    elif ((difference_mem>10)); then
        (( mem_per_rule = total_mem / num_rules))
        err "Command execution used $total_mem K memory ($mem_per_rule K per rule), baseline memory is $baseline_mem K ($difference_mem % difference)"
    else
        success "Command execution took $real_time sec, baseline time is $baseline_time sec ($difference_time % difference), used $total_mem K memory ($difference_mem % difference)"
    fi

    check_num_rules $num_rules $NIC
}

function perf_test() {
    local rules_per_file=$1
    local classifier=$2
    local baseline_ins=$3
    local baseline_del=$4
    local baseline_mem=$5

    tc_batch 0 "dev $NIC" $total $rules_per_file "$classifier"
    reset_tc_nic $NIC

    echo "Insert rules"
    run_benchmark_time_mem add $total $baseline_ins $baseline_mem

    echo "Delete rules"
    run_benchmark_time del 0 $baseline_del
}

title "Test $num_tc tc instance(s) with $total L2 rules"
perf_test $per_file "" $PERF_TC_L2_INSERT $PERF_TC_L2_DELETE $PERF_TC_L2_MEMORY

title "Test $num_tc tc instance(s) with $total L2+5tuple rules"
perf_test $per_file "src_ip 192.168.111.1 dst_ip 192.168.111.2 ip_proto udp dst_port 1 src_port 1" $PERF_TC_5T_INSERT $PERF_TC_5T_DELETE $PERF_TC_5T_MEMORY

test_done
