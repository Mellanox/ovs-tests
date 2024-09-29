#!/bin/bash
#
# Test OVS-DPDK add/del 2 ports multiple times.
#
# Bug SW #4093658: [OVS-DOCA] errors in logs after re-creating geneve tunnel on both ports after deletion.
#
my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function run() {
    local i

    start_clean_openvswitch

    title "Add/del ovs 2 ports multiple times"
    ovs_add_bridge ov1
    ovs_add_bridge ov2
    for i in `seq 4`; do
        ovs_add_dpdk_port ov1 $NIC
        ovs_add_dpdk_port ov2 $NIC2
        ovs-vsctl del-port $NIC
        ovs-vsctl del-port $NIC2
    done
    ovs-vsctl del-br ov1 || err "Failed to del br"
    ovs-vsctl del-br ov2 || err "Failed to del br"
    journalctl_for_test | grep -i "vswitchd.*killed.*SEGV"
    if [ $? -eq 0 ]; then
        err "openvswitch crashed"
    fi
}

run
trap - EXIT
cleanup_test
test_done
