#!/bin/bash
#
# Bug SW #1601565: [JD] long time to bring up reps
#

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
        err "Expected to take less than $x ms"
    else
        success "took $t ms"
    fi
}

function test_time_for_net_up() {
    local dev=$1
    echo "test time for $dev up"
    ip link set dev $dev down
    test_time_cmd 180 "ip link set dev $dev up"
}

function test_reps() {
    local want=$1

    title "Test $want REPs"

    config_sriov 0 $NIC
    echo "Config $want VFs"
    time config_sriov $want $NIC
    unbind_vfs $NIC

    test_time_for_net_up $NIC

    echo "Set switchdev"
    time switch_mode_switchdev $NIC

    test_time_for_net_up $NIC

    enable_legacy
    config_sriov 2 $NIC
}


trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

test_reps 8
test_reps 16

echo "Cleanup"
cleanup
check_syndrome
test_done
