#!/bin/bash
#
#
# Bug SW #1487302: [upstream] failing to set mode switchdev when we have 127 vfs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    config_sriov 2 $NIC
    # restore autoprobe
    if [ $probe == 1 ]; then
        echo 1 > $probe_fs
    fi
}

function test_127_reps() {
    local want=127

    title "Test 127 REPs"

    switch_mode_legacy
    echo 0 > $probe_fs
    echo "Config $want VFs"
    config_sriov $want $NIC
    switch_mode_switchdev

    echo "Verify"
    mac=`cat /sys/class/net/$NIC/address | tr -d :`
    count=`grep $mac /sys/class/net/*/phys_switch_id 2>/dev/null | wc -l`
    # decr 1 for pf
    let count-=1
    if [ $count != $want ]; then
        err "Found $count reps but expected $want"
    fi
}


trap cleanup EXIT
probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
probe=`cat $probe_fs`
test_127_reps
echo Cleanup
cleanup
test_done
