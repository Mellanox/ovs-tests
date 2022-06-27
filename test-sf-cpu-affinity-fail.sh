#!/bin/bash
#
# Test set cpu affinity for a sf over a disabled cpu should fail.
# [MLNX OFED] Bug SW #2793688: [ASAP, OFED 5.5, SFs] set cpu affinity for a sf over a disabled cpu should fail

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

function cleanup() {
    disable_irq_reguest_debug
    enable_cpu1
    remove_sfs >/dev/null
}

trap cleanup EXIT

function disable_cpu1() {
    echo 0 > /sys/bus/cpu/devices/cpu1/online
}

function enable_cpu1() {
    echo 1 > /sys/bus/cpu/devices/cpu1/online
}

function config() {
    title "Config"
    enbale_irq_reguest_debug
    create_sfs 1

    title "SFs Netdev Rep Info"
    SF=`sf_get_netdev 1`
    SF_DEV=`sf_get_dev 1`
    echo "SF: $SF, DEV: $SF_DEV"

    title "Disabling CPU #1"
    disable_cpu1
}

function test_cpu_affinity_fail() {
    title "Trying to set SF CPU affinity to CPU #1"
    __ignore_errors=1
    sf_set_cpu_affinity $SF_DEV 1
    local rc=$?
    __ignore_errors=0

    if [ "$rc" != "0" ]; then
        success
    else
        err "Expected to fail"
    fi

}

enable_switchdev $NIC
config
test_cpu_affinity_fail
cleanup
trap - EXIT
test_done
