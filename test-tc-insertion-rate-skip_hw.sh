#!/bin/bash
#
# Measure rule insertion rate and memory consumption in software-only mode.
#
# IGNORE_FROM_TEST_ALL
#

baseline_file=${1:-insertion-rate-skip_hw-data.txt}

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

run_perf_test "$baseline_file" "all 1000000 10 skip_hw"
test_done
