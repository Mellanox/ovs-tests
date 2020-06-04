#!/bin/bash
#
# Test setting reps on both ports
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    restore_sriov_autoprobe
}

trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

config_sriov 0 $NIC
config_sriov 0 $NIC2

title "Config 3 VFs on $NIC"
config_reps 3 $NIC
count_reps 4 $NIC

title "Config 3 VFs on $NIC2"
config_reps 3 $NIC2
count_reps 8 $NIC

echo "Cleanup"
config_sriov 0 $NIC2
config_sriov 2 $NIC
cleanup
check_syndrome
test_done
