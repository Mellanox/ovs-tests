#!/bin/bash
#
# Check if logs contains errors before running usual tests (after boot)
#
# Bug SW #2292924: WARNING: possible circular locking dependency detected
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

__uptime_seconds=`awk '{print $1}' /proc/uptime | cut -d. -f1`

max_uptime=1800
title "Check if uptime is less than $max_uptime"
if [ $__uptime_seconds -gt $max_uptime ]; then
    echo "Aborting"
else
    title "Check if a test ran before this one"

    tmp=`dmesg | grep "TEST test-" | grep $TESTNAME`
    count=`dmesg | grep "TEST test-" | grep -v $TESTNAME | wc -l`

    if [ "$tmp" == "" ]; then
        # test grep is ok
        fail "Expected a match"
    elif [ $count -ne 0 ]; then
        log "Other tests already running."
    else
        title "Check dmesg"
        check_for_errors_log ${__uptime_seconds}
    fi
fi

if [[ $? -eq 0 ]]; then
    success "TEST PASSED"
else
    fail "TEST FAILED"
fi
