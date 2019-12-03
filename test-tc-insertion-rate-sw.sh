#!/bin/bash
#
# Measure rule insertion rate and memory consumption in sw-steering offloads
# mode.
#
# IGNORE_FROM_TEST_ALL
#

BASE_LINE_FILE=${BASE_LINE_FILE:-/tmp/insertion-rate-sw-data.txt}
user_act_flags=$1

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

config_sriov 2 $NIC
enable_legacy $NIC
set_steering_sw
enable_switchdev $NIC

run_perf_test "$BASE_LINE_FILE" all 1000000 10 " " $user_act_flags

enable_legacy $NIC
set_steering_fw
test_done
