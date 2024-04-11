#! /usr/bin/env bash
#
# Test OVS with mix of rep from pf0 but add pf1 to the bridge.
#
# The issue seems to be when ovs tried to attach the rep first and then pf1.
#
# [OVS] Bug SW #3859202: [ovs-doca] backtrace after restart openvswitch with ovs-doca

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_interfaces NIC NIC2

# the more reps the easier to reproduce as ovs will have more
# chances choosing to load a rep before pf1.
reps_count=4
config_sriov $reps_count $NIC

enable_switchdev
enable_switchdev $NIC2
bind_vfs

trap cleanup_test EXIT

function run() {
    start_clean_openvswitch
    config_simple_bridge_with_rep $reps_count false br-phy
    ovs_add_dpdk_port br-phy $NIC2
    ovs-vsctl show
    # issue can start here
    echo "waiting"
    sleep 5
    # lets try a restart
    restart_openvswitch

    ovs_clear_bridges
    config_sriov 2 $NIC
}

run
trap - EXIT
cleanup_test
test_done
