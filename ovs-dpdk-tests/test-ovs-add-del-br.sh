#!/bin/bash
#
# Test OVS-DPDK add/del bridge multiple times.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function run() {
    local i

    title "Add/del ovs bridge multiple times"
    for i in `seq 4`; do
        ovs-vsctl add-br ov1 || err "Failed to add br"
        ovs-vsctl del-br ov1 || err "Failed to del br"
    done
    journalctl_for_test | grep -i "vswitchd.*killed.*SEGV"
    if [ $? -eq 0 ]; then
        err "openvswitch crashed"
    fi
}

run
trap - EXIT
cleanup_test
test_done
