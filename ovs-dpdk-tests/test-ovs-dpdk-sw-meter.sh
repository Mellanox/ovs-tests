#!/bin/bash
#
# Test OVS-DPDK software rate limiting
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function config_topology() {
    local pf0vf0_r=`get_port_from_pci $PCI 0`
    local pf0vf1_r=`get_port_from_pci $PCI 1`
    local bridge="br-phy"

    config_simple_bridge_with_rep 2 true $bridge

    ovs-vsctl add-port $bridge int -- set interface int type=internal

    ovs_set_port_sw_meter $pf0vf0_r pps 3 1
    ovs_set_port_sw_meter $pf0vf1_r pps 3 1

    config_ns ns0 $VF1 $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

# To test SW meter add a rule that we don't offload
# to force the traffic to miss to SW.
function add_none_offload_rule() {
    local pf0vf0_r=`get_port_from_pci $PCI 0`
    local pf0vf1_r=`get_port_from_pci $PCI 1`

    ovs-ofctl add-flow br-phy in_port=$pf0vf0_r,actions=int,$pf0vf1_r
}

function run() {
    cleanup_test
    config_topology
    restart_openvswitch_nocheck
    add_none_offload_rule
    send_metered_ping
}

run
trap - EXIT
cleanup_test
test_done
