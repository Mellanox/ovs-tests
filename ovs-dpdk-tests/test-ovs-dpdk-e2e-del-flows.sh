#!/bin/bash
#
# Test OVS-DPDK E2E-CACHE flow deletion
#
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function add_openflow_rules1() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "icmp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules1

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1

    # check number of flows
    x=$(ovs-appctl dpctl/dump-e2e-flows |wc -l)
    debug "Number of merged flows: $x"

    del_openflow_rules br-phy
    y=$(ovs-appctl dpctl/dump-e2e-flows |wc -l)
    debug "Number of merged flows after deletion: $y"
    if [ $y -ne 0 ]; then
        err "Flows not deleted"
    fi

}

run
trap - EXIT
cleanup_test
test_done
