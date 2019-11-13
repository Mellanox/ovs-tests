#!/bin/bash
#
# Measure rule insertion rate and memory consumption in sw-steering offloads
# mode with no_percpu action flag.
#
# IGNORE_FROM_TEST_ALL
#

BASE_LINE_FILE=insertion-rate-sw-no_percpu-data.txt ./test-tc-insertion-rate-sw.sh no_percpu
