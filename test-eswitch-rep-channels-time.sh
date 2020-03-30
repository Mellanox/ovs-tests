#!/bin/bash
#
# Change number of channels of representor
#
# Related to Bug SW #1601565: [JD] long time to bring up reps
#
# results tested with 16 reps
# bad: 400ms
# good: 30ms

my_dir="$(dirname "$0")"
. $my_dir/common.sh


probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
probe=0
function disable_sriov_autoprobe() {
    if [ -e $probe_fs ]; then
        probe=`cat $probe_fs`
        echo 0 > $probe_fs
    fi
}

function restore_sriov_autoprobe() {
    if [ $probe == 1 ]; then
        echo 1 > $probe_fs
    fi
}

function cleanup() {
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

function test_time_set_channels() {
    local dev=$1
    echo "test time set channels for $dev"
    ethtool -L $dev combined 1
    test_time_cmd $expected_time "ethtool -L $dev combined 4"
}

function get_time_set_channels() {
    local dev=$1

    ethtool -L $dev combined 1

    local t1=`get_ms_time`
    ethtool -L $dev combined 4
    local t2=`get_ms_time`
    let t=t2-t1
    if [ $t = "" ]; then
        err "Got time 0"
    fi

    ethtool -L $dev combined 1
}

expected_time=0

function test_reps() {
    local want=$1

    config_sriov 0 $NIC

    title "Test $want REPs"

    echo "Config $want VFs"
    time config_sriov $want $NIC

    echo "Set switchdev"
    unbind_vfs $NIC
    time switch_mode_switchdev $NIC
    if [ $expected_time -eq 0 ]; then
        get_time_set_channels $REP
        let expected_time=$t+50
    fi
    test_time_set_channels $REP

    enable_legacy
    config_sriov 2 $NIC
}


trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

# test 1 rep for comparison point
test_reps 1
test_reps 8
test_reps 16

echo "Cleanup"
cleanup
check_syndrome
test_done
