#!/bin/bash
#
# Test dp-hash after vxlan encap
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

IB_PORT=`get_port_from_pci`
trap cleanup_test EXIT

function config() {
    cleanup_test
    config_tunnel "vxlan" 1 br-phy br-phy
    bf_wrap "ip link add dev dummy type veth peer name rep-dummy"
    ovs-vsctl add-port br-phy rep-dummy
    ovs-vsctl show
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-group br-phy group_id=1,type=select,bucket=watch_port=$IB_PORT,output:$IB_PORT,bucket=watch_port=rep-dummy,output:rep-dummy

    ovs-ofctl add-flow br-phy in_port=$IB_PF0_PORT0,actions=vxlan_br-phy
    ovs-ofctl add-flow br-phy in_port=vxlan_br-phy,actions=$IB_PF0_PORT0

    ovs-ofctl add-flow br-phy in_port=LOCAL,actions=group:1
    ovs-ofctl add-flow br-phy in_port=$IB_PORT,actions=LOCAL

    debug "OVS groups:"
    ovs-ofctl dump-groups br-phy --color
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    config_remote_tunnel vxlan
    add_openflow_rules

    verify_ping $REMOTE_IP ns0
    generate_traffic "remote" $LOCAL_IP
    ovs-appctl dpctl/dump-flows -m
}

run
bf_wrap "ip link del dummy"
trap - EXIT
cleanup_test
test_done
