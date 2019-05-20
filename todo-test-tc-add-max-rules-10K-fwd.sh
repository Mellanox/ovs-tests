#!/bin/bash
#
# Not relevant for ConnectX-4 as it only supports 64K rules.
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

TOTAL_COUNT=10000 \
ACTION="mirred" \
TIMEOUT=2m \
    $my_dir/todo-test-tc-add-max-rules.sh
