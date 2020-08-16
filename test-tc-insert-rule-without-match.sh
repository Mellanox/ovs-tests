#!/bin/bash
#
# Bug SW #1338214: [TC] failure to create rule without any match
#
# In error we reproduce this syndrome:
# BAD_PARAM           | 0x7E1580 |  create_flow_group: outer_headers valid bit is set, but headers are zero
#
# Currently in ConnectX-4 we will still get syndrome about missing dst mac.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function tc_filter() {
    eval tc filter $@ 2>&1
}

function test_in_switchdev() {
    title "Test rule without match in switchdev mode"
    enable_switchdev
    do_test
}

function test_in_legacy() {
    title "Test rule without match in legacy mode"
    enable_legacy
    do_test
}

function do_test() {
    reset_tc $NIC
    start_check_syndrome
    tc_filter add dev $NIC parent ffff: prio 1 flower skip_sw action drop
    err=$?
    if [ $DEVICE_IS_CX4 == 1 ]; then
        echo "In ConnectX-4 we expect to fail with syndrome of missing dst mac."
        expect_syndrome "0x29cdba" && success
    else
        # ConnectX-5
        if [ $err == 0 ]; then
            success
        else
            err "Failed to add rule"
        fi
        check_syndrome
    fi

    reset_tc $NIC
}

config_sriov
test_in_legacy
test_in_switchdev
test_done
