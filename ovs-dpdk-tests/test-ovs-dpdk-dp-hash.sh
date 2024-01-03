#!/bin/bash
#
# Test dp-hash
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

function cleanup() {
    ovs_conf_remove hw-offload-ct-size
    cleanup_test
}
trap cleanup EXIT

function config() {
    ovs_conf_set hw-offload-ct-size 0
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    ovs-vsctl show
}

function add_openflow_rules() {
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-group $bridge group_id=1,type=select,bucket=watch_port=$IB_PF0_PORT1,output:$IB_PF0_PORT1
    ovs-ofctl add-flow $bridge "in_port=$IB_PF0_PORT0,actions=group=1"
    ovs-ofctl add-flow $bridge "in_port=$IB_PF0_PORT1,actions=$IB_PF0_PORT0"

    debug "OVS groups:"
    ovs-ofctl dump-groups $bridge --color

    ovs_ofctl_dump_flows
}

function run() {
    config
    add_openflow_rules
    sleep 2
    verify_ping
    generate_traffic "local" $LOCAL_IP ns1
    ovs-appctl dpctl/dump-flows -m
}

run
trap - EXIT
cleanup
test_done
