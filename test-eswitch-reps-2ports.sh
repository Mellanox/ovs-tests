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
disable_sriov_autoprobe

config_sriov 0 $NIC
config_sriov 0 $NIC2

reps_per_port=2
let exp=reps_per_port+1
# newer kernels have phys_switch_id readable also when sriov is disabled or in legacy
if cat /sys/class/net/$NIC2/phys_switch_id &>/dev/null ; then
    let exp+=1
fi

title "Config $reps_per_port VFs on $NIC"
config_reps $reps_per_port $NIC
count_reps $exp $NIC

title "Config $reps_per_port VFs on $NIC2"
config_reps $reps_per_port $NIC2
let exp=reps_per_port*2+2
count_reps $exp $NIC

echo "Cleanup"
config_sriov 0 $NIC2
config_sriov 2 $NIC
cleanup
test_done
