#!/bin/bash
#
# Measure rule insertion rate and memory consumption in software-only mode.
#
# IGNORE_FROM_TEST_ALL
#

BASE_LINE_FILE=${BASE_LINE_FILE:-insertion-rate-skip_hw-data.txt}
user_act_flags=$1

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

run_perf_test "$BASE_LINE_FILE" all 1000000 10 skip_hw $user_act_flags
test_done
