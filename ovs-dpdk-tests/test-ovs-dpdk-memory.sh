#! /usr/bin/env bash
#
# Test OVS memory usage in several configurations:
#   no bridges
#   one uplink
#   two uplinks

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

N=$(count_available_vf $NIC)
N2=$(count_available_vf $NIC2)

require_interfaces NIC NIC2

config_sriov $N $NIC
config_sriov $N2 $NIC2

enable_switchdev
enable_switchdev $NIC2

unbind_vfs
bind_vfs

trap cleanup_test EXIT

function run() {
    start_clean_openvswitch

    title "Test OVS memory usage"
    ovs_memory "Baseline"
    config_simple_bridge_with_rep $N true br0 $NIC
    ovs_memory "1-uplink-$N-reps"
    config_simple_bridge_with_rep $N2 true br1 $NIC2
    ovs_memory "2-uplinks-$((N+N2))-reps"
}

run
trap - EXIT
cleanup_test
test_done
