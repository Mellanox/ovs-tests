#!/bin/bash
#
# Bug SW #1487302: [upstream] failing to set mode switchdev when we have 127 vfs
# Bug SW #1601565: [JD] long time to bring up reps
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    restore_sriov_autoprobe
}

function test_reps() {
    local want=$1

    title "Config $want VFs on $NIC"
    config_reps $want $NIC
    (( want += 1 ))        # reps will be verified by switch id so add one for pf port.
    count_reps $want $NIC

    enable_legacy
    config_sriov 2 $NIC
}


trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

test_reps 32
if [ $TEST_FAILED -eq 0 ] || [ -e $probe_fs ]; then
    test_reps 127
else
    err "Skipping 127 reps case due to failure in prev case"
fi

echo "Cleanup"
cleanup
check_syndrome
test_done
