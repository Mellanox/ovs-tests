#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to service on same node
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-test.sh

require_interfaces NIC

read_k8s_topology_pod_service_same_node

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
}

function config_test() {
    config_ovn_single_node

    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    run_local_traffic "icmp6_is_not_offloaded" "icmp4_is_not_offloaded" $SERVER_VF $LB_IPV4 $LB_IPV6
}

TRAFFIC_INFO['local_traffic']=1

clean_up_test

trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
