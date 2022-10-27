#!/bin/bash
#
# Bug SW #1601565: long time to bring up reps
# Bug SW #1605626: [upstream] long time to bring up reps
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    config_sriov 2
    restore_sriov_autoprobe
}

function test_time_cmd() {
    local x=$1
    local cmd=$2
    local t1=`get_ms_time`
    time $cmd
    local t2=`get_ms_time`
    let t=t2-t1
    if [ $t -gt $x ]; then
        err "Took $t but expected less than $x ms"
    else
        success "took $t ms (max $x)"
    fi
}

function get_time_for_net_up() {
    local dev=$1
    ip link set $dev down
    local t1=`get_ms_time`
    ip link set $dev up
    local t2=`get_ms_time`
    let t=t2-t1
    if [ $t = "" ]; then
        err "Got time 0"
    fi
}

function test_time_for_net_up() {
    local dev=$1
    title "- test time for $dev up"
    ip link set dev $dev down
    test_time_cmd $expected_time "ip link set dev $dev up"
}

expected_time=0

function test_reps() {
    local want=$1

    # get compare time for single interface when sriov is disabled
    config_sriov 0 $NIC
    if [ $expected_time -eq 0 ]; then
        get_time_for_net_up $NIC
        let expected_time=$t+50
    fi

    title "Test $want REPs"

    title "- test legacy $want VFs"
    time config_sriov $want $NIC
    # not testing link up time in legacy mode currently
    #test_time_for_net_up $NIC

    title "- test switchdev"
    unbind_vfs $NIC
    time switch_mode_switchdev $NIC
    test_time_for_net_up $NIC
}


trap cleanup EXIT
disable_sriov_autoprobe

test_reps 8
test_reps 16

echo "Cleanup"
trap - EXIT
cleanup
test_done
