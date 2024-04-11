#!/bin/bash
#
# Test OVS-DPDK Hairpin in MPES mode
#
#
# Setup Diagram
#
# (Hairpin server (MPESW))              (Traffic server)
#        Local                               Remote
# ┌─────────────────────┐            ┌─────────────────────┐
# │                     │            │                     │
# │                     │            │           ┌───┐     │
# │                     │            │           │VF0│     │
# │                     │            │           ├───┴┐    │
# │                     │            │           │ NS0│    │
# │  ┌────────┐         │            │     ┌──┬──┴────┘    │
# │  │        ├───┐     │            │  ┌──▼──┤            │
# │  │   OVS  │PF1├─────┼────────────┤  │ OVS │            │
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

min_nic_cx6dx
require_remote_server

trap cleanup EXIT

function cleanup() {
    title "Cleaning up local"
    cleanup_mpesw
    cleanup_test
}

function add_openflow_rules() {
    local pci=`get_pf_pci`
    local port=`get_port_from_pci $pci`
    local pci2=`get_pf_pci2`
    local port2=`get_port_from_pci $pci2`

    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp, actions=normal"
    ovs-ofctl add-flow $bridge "in_port=$port2,ip actions=IN_PORT"

    debug "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function set_interfaces_up() {
    ip link set $NIC up
    ip link set $NIC2 up
}

function config_ovs() {
    local pci2=`get_pf_pci2`
    local port2=`get_port_from_pci $pci2`

    title "Config OVS"
    start_clean_openvswitch
    config_simple_bridge_with_rep 0
    ovs-vsctl add-port br-phy $port2 -- set interface $port2 type=dpdk options:dpdk-devargs="$PCI,dv_xmeta_en=4,dv_flow_en=2,representor=pf1"
    ovs-vsctl show
}

function add_remote_openflow_rules() {
    local pci=`get_pf_pci2`
    local pf1=`get_port_from_pci $pci`
    local rep0=`get_port_from_pci $pci 0`
    local rep1=`get_port_from_pci $pci 1`
    local vf0=`get_vf 0 $NIC2`
    local vf1=`get_vf 1 $NIC2`
    local vf0_mac=`on_remote_exec get_dev_mac $vf0`
    local vf1_mac=`on_remote_exec get_dev_mac $vf1`


    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "ip,in_port="$rep0" actions=$pf1"
    ovs-ofctl add-flow $bridge "ip,in_port="$rep1" actions=$pf1"
    ovs-ofctl add-flow $bridge "ip,in_port="$pf1",dl_dst=$vf1_mac actions=$rep1" #MAC learning
    ovs-ofctl add-flow $bridge "ip,in_port="$pf1",dl_dst=$vf0_mac actions=$rep0" #MAC learning

    debug "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function config_remote() {
    local vf0=`get_vf 0 $NIC2`
    local vf1=`get_vf 1 $NIC2`

    config_simple_bridge_with_rep 2 true br-phy $NIC2
    add_remote_openflow_rules
    config_ns ns0 $vf0 $LOCAL_IP
    config_ns ns1 $vf1 $REMOTE_IP
}

function config() {
    config_mpesw
    restart_openvswitch_nocheck
    config_ovs
    add_openflow_rules
    on_remote_exec "config_remote"
}

function run_test() {
    config
    on_remote_exec "verify_ping $REMOTE_IP
                    generate_traffic "local" $LOCAL_IP ns1"
    check_dpdk_offloads $LOCAL_IP
}

run_test
trap - EXIT
cleanup
test_done
