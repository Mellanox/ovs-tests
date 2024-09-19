#!/bin/bash
#
# Test OVS DPDK mirror to cross eswitch PF
#
# Require external server
#
# Bug #4074509: [OVS-DOCA] Mirroring cross eswitch without multiport eswitch causes trace
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

IP2=1.1.1.15

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev
enable_switchdev $NIC2
bind_vfs

trap cleanup_test EXIT

function config() {
    local pci=`get_pf_pci2`

    cleanup_test

    config_simple_bridge_with_rep 1
    ovs-vsctl add-port br-phy pf1 -- set interface pf1 type=dpdk options:dpdk-devargs="$pci,$DPDK_PORT_EXTRA_ARGS"

    ovs-ofctl add-flow br-phy "in_port=pf0vf0,actions=pf0,pf1"

    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $IP2
}

function run() {
    config
    config_remote_nic

    t=5
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
