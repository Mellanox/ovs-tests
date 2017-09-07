#!/bin/bash
#
# Test 1M rules
# Not relevant for ConnectX-4 as it only supports 64K rules.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

TIMEOUT=10m \
CASE_NIC=ens1f0 \
CASE_TWO_PORTS=0 \
CASE_SKIP=skip_sw \
CASE_COUNT=1000000 \
CASE_INDEX=0 \
    $my_dir/test-tc-max-rules.sh
