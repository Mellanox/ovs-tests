#!/bin/bash
#
# Test ovs with SFs using sfnum 4096
#
# [MLNX DPDK] Bug SW #3590886: cannot add SF repr as a valid port in OVS with DOCA enabled with index greater than 4095

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common-sf.sh

enable_switchdev

function cleanup() {
    cleanup_test
    remove_sfs
}

trap cleanup EXIT

function run() {
    cleanup
    __create_sfs 4095 4096
    ovs_add_bridge
    ovs_add_port "PF"
    ovs_add_port "SF" 4095
    ovs_add_port "SF" 4096
    ovs-vsctl show
    ovs-vsctl show | grep -q "error:"
    if [ $? -ne 0 ]; then
        success
    else
        err "Some ports failed."
    fi
}

run
trap - EXIT
cleanup
test_done
