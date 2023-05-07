#!/bin/bash
#
# Verify traffic between VF and underlay configured with OVN gateway router is offloaded
#

HAS_REMOTE=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-basic-test.sh

read_distributed_gateway_port_topology

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
    on_remote_exec "__reset_nic"
}

function config_test() {
    ovn_single_node_external_config
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    config_ovn_external_server
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    run_remote_traffic "icmp6_is_not_offloaded" $SERVER_PORT
}

TRAFFIC_INFO['server_ns']=""
TRAFFIC_INFO['server_verify_offload']=""

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
