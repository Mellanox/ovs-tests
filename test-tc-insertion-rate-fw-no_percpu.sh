#!/bin/bash
#
# Measure rule insertion rate and memory consumption in firmware mode with
# no_percpu action flag.
#
# IGNORE_FROM_TEST_ALL
#

export BASE_LINE_FILE=${BASE_LINE_FILE:-insertion-rate-fw-no_percpu-data.txt}
my_dir="$(dirname "$0")"

. $my_dir/test-tc-insertion-rate-fw.sh no_percpu
