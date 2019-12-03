#!/bin/bash
#
# Measure rule insertion rate and memory consumption in sw-steering offloads
# mode with no_percpu action flag.
#
# IGNORE_FROM_TEST_ALL
#

export BASE_LINE_FILE=${BASE_LINE_FILE:-/tmp/insertion-rate-sw-no_percpu-data.txt}
my_dir="$(dirname "$0")"

. $my_dir/test-tc-insertion-rate-sw.sh no_percpu
