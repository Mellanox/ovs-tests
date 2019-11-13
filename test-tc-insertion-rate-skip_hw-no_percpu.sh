#!/bin/bash
#
# Measure rule insertion rate and memory consumption in software-only mode with
# no_percpu action flag.
#
# IGNORE_FROM_TEST_ALL
#

BASE_LINE_FILE=insertion-rate-skip_hw-no_percpu-data.txt ./test-tc-insertion-rate-skip_hw.sh no_percpu
