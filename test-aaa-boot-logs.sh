#!/bin/bash
#
# Check if logs contains errors before running usual tests (after boot)
#
# Bug SW #2292924: WARNING: possible circular locking dependency detected
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# 2860496 - [ASAP, OFED 5.5, SW steering 5.14] mlx5_esw_offloads_devcom_event:3123:(pid 370963): esw offloads devcom event failure, event 0 err -22
if [ `uname -r` == "5.14.0_mlnx" ]; then
    add_expected_error_msg "esw offloads devcom event failure, event 0 err -22"
fi

__uptime_seconds=`awk '{print $1}' /proc/uptime | cut -d. -f1`

max_uptime=1800
title "Check if uptime is less than $max_uptime"
if [ $__uptime_seconds -gt $max_uptime ]; then
    log "Nothing to do"
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
        check_for_errors_log today
    fi
fi

if [[ $? -eq 0 ]]; then
    success "TEST PASSED"
else
    fail "TEST FAILED"
fi
