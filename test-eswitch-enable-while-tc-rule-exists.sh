#!/bin/bash
#
# Test adding rules in sriov disabled mode, then switching back to switchdev
# (in cleanup). If bug occurs, these take all 4M and 1M tables, so when
# we enable sriov (none -> legacy), there is no 4M table available to legacy table.
#
# Bug SW #3105430 [ASAP, OFED 5.7] No space left on device when trying to create vfs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
   reset_tc $NIC
   config_sriov 2 $NIC
}
trap cleanup EXIT

function run() {
    title "Add rules when sriov disabled"
    config_sriov 0 $NIC
    reset_tc $NIC
    for i in `seq 1 99`; do
        tc_filter add dev $NIC protocol ip ingress prio $i flower dst_mac aa:bb:cc:dd:ee:ff skip_sw action drop
    done
    title "Config sriov"
    config_sriov 2 $NIC
}

run
cleanup
trap - EXIT
test_done
