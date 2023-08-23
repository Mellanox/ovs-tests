#!/bin/bash
#
# Test OVS-DPDK Hairpin basic flow
# Require external server
#
#
# Setup Diagram
#
#     (Hairpin server)                    (Traffic server)
#        Local                            Remote
# ┌─────────────────────┐            ┌─────────────────────┐
# │                     │            │                     │
# │                     │            │           ┌───┐     │
# │                     │            │           │VF0│     │
# │                     │            │           ├───┴┐    │
# │                     │            │           │ NS0│    │
# │  ┌────────┐         │            │     ┌──┬──┴────┘    │
# │  │        ├───┐     │            │  ┌──▼──┤            │
# │  │   OVS  │PF ├─────┼────────────┤  │ OVS │            │
# │  │        ├───┘     │            │  └──▲──┤  ┌─────┐   │
# │  └────────┘         │            │     └──┴──┤ NS1 │   │
# │                     │            │           ├───┬─┘   │
# │                     │            │           │VF1│     │
# │                     │            │           └───┘     │
# │                     │            │                     │
# └─────────────────────┘            └─────────────────────┘
#
# The diagrams were drawn with https://asciiflow.com/ and edited in VIM.
#`
# PS: We make sure traffc from VF0 to VF1 get out on the wire
#     using openflow rules.

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup EXIT

VF0_MAC=e4:95:7b:08:00:02
VF1_MAC=e4:95:7b:08:00:03

function cleanup() {
    start_clean_openvswitch
    cleanup_test
    on_remote_exec "start_clean_openvswitch
                    cleanup_test"
}

function add_remote_openflow_rules() {
    local pci=`get_pf_pci`
    local ib_pf=`get_port_from_pci $pci`
    local ib_vf0=`get_port_from_pci $pci 0`
    local ib_vf1=`get_port_from_pci $pci 1`
    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "ip,in_port="$ib_vf0" actions=$ib_pf"
    ovs-ofctl add-flow $bridge "ip,in_port="$ib_vf1" actions=$ib_pf"
    ovs-ofctl add-flow $bridge "ip,in_port="$ib_pf",dl_dst=$VF1_MAC actions=$ib_vf1" #MAC learning
    ovs-ofctl add-flow $bridge "ip,in_port="$ib_pf",dl_dst=$VF0_MAC actions=$ib_vf0" #MAC learning

    debug "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function add_openflow_rules() {
    local pci=`get_pf_pci`
    local port=`get_port_from_pci $pci`
    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "in_port=$port,ip,actions=in_port"

    debug "OVS flow rules on remote:"
    ovs-ofctl dump-flows $bridge --color
}

function config_remote() {
    local vf0=`get_vf 0`
    local vf1=`get_vf 1`

    ip link set dev $vf0 address $VF0_MAC
    ip link set dev $vf1 address $VF1_MAC
    config_simple_bridge_with_rep 2
    add_remote_openflow_rules
    config_ns ns0 $vf0 $LOCAL_IP
    config_ns ns1 $vf1 $REMOTE_IP
}

function config() {
    config_simple_bridge_with_rep 0
    add_openflow_rules
}

function run_test() {
    cleanup
    config
    on_remote_exec "config_remote
                    verify_ping $REMOTE_IP
                    generate_traffic "local" $LOCAL_IP ns1"
    check_dpdk_offloads
}

run_test
cleanup
trap - EXIT
test_done
