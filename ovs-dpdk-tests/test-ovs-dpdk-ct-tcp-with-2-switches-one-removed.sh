#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT on two bridges
# each with a different esw manager.
# This test is different from test-ovs-dpdk-ct-tcp-with-2-switches.sh
# since it tries to delete the PF on one of the bridges which triggers
# datapath reconfigur expecting not to break anything.
#
# Requires external server.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_devices

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 1 true "br-phy" $NIC
    config_simple_bridge_with_rep 1 true "br-phy-2" $NIC2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns0 `get_vf 0 $NIC2` $LOCAL_IP2
}

function config_remote() {
    config_remote_arm_bridge
    config_remote_arm_bridge "br-phy-2" $NIC2
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip a flush dev $REMOTE_NIC2
               ip a add $REMOTE_IP2/24 dev $REMOTE_NIC2
               ip l set dev $REMOTE_NIC2 up"
}

function run() {
    config
    config_remote

    ovs_add_ct_rules "br-phy" tcp
    verify_ping $REMOTE_IP
    generate_traffic "remote" $LOCAL_IP

    ovs_add_ct_rules "br-phy-2" tcp
    verify_ping $REMOTE_IP2
    generate_traffic "remote" $LOCAL_IP2

    local pci=$(get_pf_pci2)
    local port=`get_port_from_pci $pci`

    debug "Removing $port"
    ovs-vsctl del-port $port

    generate_traffic "remote" $LOCAL_IP
}

run
check_counters
trap - EXIT
cleanup_test
test_done
