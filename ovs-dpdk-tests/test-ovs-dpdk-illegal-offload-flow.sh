#!/bin/bash
#
# Test illegal offlaod flow.
# Send traffic from NIC2 to VF of NIC1.
# We expect not to have offload.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common.sh

require_remote_server

require_interfaces REP NIC NIC2
config_sriov 1
config_sriov 1 $NIC2
enable_switchdev
enable_switchdev $NIC2
on_remote_exec enable_legacy
on_remote_exec enable_legacy $NIC2
unbind_vfs
bind_vfs
unbind_vfs $NIC2
bind_vfs $NIC2

trap cleanup EXIT

function cleanup() {
    cleanup_test
    on_remote_exec cleanup_test
}

function config() {
    cleanup_test
    on_remote_exec cleanup_test
    debug "Restarting OVS"
    start_clean_openvswitch
    debug "Configure OVS bridge"
    config_simple_bridge_with_rep 1 true br-phy $NIC
    config_simple_bridge_with_rep 1 true br-phy $NIC2
    config_ns ns0 $VF 1.1.1.1
    config_ns ns1 `get_vf 0 $NIC2` 1.1.1.2
    ovs_conf_set max-idle 300000
}

function config_remote() {
    on_remote_exec "config_ns ns0 $NIC 1.1.1.3"
    on_remote_exec "config_ns ns1 $NIC2 1.1.1.4"
}

function check_no_offloaded_connections() {
    local expected_connections=0
    local current_connections

    for (( i=0; i<3; i++ )); do
        current_connections=$(ovs-appctl dpctl/dump-flows -m | grep icmp | grep offloaded | wc -l)
        if (( $current_connections > $expected_connections )); then
            debug "Did not expect offloaded connections but found $current_connections"
            ovs-appctl dpctl/dump-flows -m --names
            fail "Found $current_connections offloaded connections, expected 0"
        else
            debug "Did not find any offloaded connections yet - revalidate"
            sleep 0.5
        fi
    done
}

function run() {
    config
    config_remote
    verify_ping 1.1.1.3 ns1 56 50
    verify_ping 1.1.1.4 ns0 56 50
    check_no_offloaded_connections
}

run
check_counters
trap - EXIT
cleanup
test_done
