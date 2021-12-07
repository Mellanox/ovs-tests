#!/bin/bash
#
# Testing adding rules in legacy mode
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"


TIMEOUT=15m
CASE_TWO_PORTS=0
CASE_NIC=$NIC
CASE_INDEX=0
CASE_SKIP=skip_sw
CASE_COUNT=60000
CASE_MODE="legacy"

. $my_dir/test-tc-max-rules.sh
