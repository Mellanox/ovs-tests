#!/bin/bash
#
# Test dp-hash SW/HW alignment
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
require_interfaces REP NIC
bind_vfs

function cleanup() {
    ovs_conf_remove hw-offload-ct-size
    cleanup_test
}

trap cleanup EXIT

remote_ips=""

function config() {
    local subnet="${REMOTE_IP::-1}"

    ovs_conf_set hw-offload-ct-size 0
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    for i in `seq 10`; do
        local addr=${subnet}${i}

        if [ "$addr" == "$LOCAL_IP" ]; then
            continue
        fi
        remote_ips="$remote_ips $addr"
    done
    config_ns ns1 $VF2 "$remote_ips"
    ovs-vsctl show
}

function validate_rules() {
    local cmd="ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'recirc_id(0)' | grep 'eth_type(0x0800)'"
    local x=$(eval $cmd | wc -l)

    if [ "$x" != "1" ]; then
        eval $cmd
        fail "Expected to have 1 flow, have $x"
    fi
}

function add_openflow_rules() {
    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-group $bridge group_id=1,type=select,selection_method=doca,bucket=output:$IB_PF0_PORT1
    ovs-ofctl add-flow $bridge "in_port=$IB_PF0_PORT0,actions=group=1"
    ovs-ofctl add-flow $bridge "in_port=$IB_PF0_PORT1,actions=$IB_PF0_PORT0"

    debug "OVS groups:"
    ovs-ofctl dump-groups $bridge --color

    ovs_ofctl_dump_flows
}

function run() {
    config
    add_openflow_rules

    for ip in $remote_ips; do
        debug "ip $ip"
        verify_ping $ip ns0 56 10 0.1
        sleep 1
        validate_rules
        ovs_flush_rules
    done
}

run
trap - EXIT
cleanup
test_done
