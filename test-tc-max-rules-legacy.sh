#!/bin/bash
#
# Testing adding rules in legacy mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


TIMEOUT=15m \
CASE_TWO_PORTS=0 \
CASE_INDEX=0 \
CASE_SKIP=skip_sw \
CASE_COUNT=60000 \
CASE_MODE="legacy" \
    $my_dir/test-tc-max-rules.sh
