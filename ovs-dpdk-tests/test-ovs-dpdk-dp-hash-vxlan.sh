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
bind_vfs

IB_PORT=`get_port_from_pci`

function cleanup() {
    ovs_conf_remove hw-offload-ct-size
    cleanup_test
}
trap cleanup EXIT

function config() {
    ovs_conf_set hw-offload-ct-size 0
    cleanup_test
    config_tunnel "vxlan" 1 br-phy br-phy
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ovs-vsctl show
}

function add_openflow_rules() {
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-group $bridge group_id=1,type=select,bucket=watch_port=$IB_PORT,output:$IB_PORT

    ovs-ofctl add-flow $bridge in_port=$IB_PF0_PORT0,actions=vxlan_$bridge
    ovs-ofctl add-flow $bridge in_port=vxlan_$bridge,actions=$IB_PF0_PORT0

    ovs-ofctl add-flow $bridge in_port=LOCAL,actions=group:1
    ovs-ofctl add-flow $bridge in_port=$IB_PORT,actions=LOCAL

    debug "OVS groups:"
    ovs-ofctl dump-groups $bridge --color

    ovs_ofctl_dump_flows
}

function run() {
    config
    config_remote_tunnel vxlan
    add_openflow_rules
    sleep 2
    verify_ping $REMOTE_IP ns0
    generate_traffic "remote" $LOCAL_IP
    ovs-appctl dpctl/dump-flows -m
}

run
trap - EXIT
cleanup
test_done
