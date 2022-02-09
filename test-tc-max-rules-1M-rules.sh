#!/bin/bash
#
# Test 1M rules
# Not relevant for ConnectX-4 as it only supports 64K rules.
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4

TIMEOUT=15m
CASE_NIC=$NIC
CASE_TWO_PORTS=0
CASE_SKIP=skip_sw
CASE_COUNT=1000000
CASE_INDEX=0

. $my_dir/test-tc-max-rules.sh
