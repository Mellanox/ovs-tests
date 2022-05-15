#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to service on single node with bluefield
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-bf-test.sh

require_interfaces NIC

read_k8s_topology_pod_service_same_node

function clean_up_test() {
    ip -all netns del
    on_bf_exec "ovn_stop_ovn_controller
                start_clean_openvswitch
                ovn_start_clean
                ovn_stop_northd_central"
}

function config_test() {
    config_bf_ovn_single_node
    config_bf_ovn_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
    config_bf_ovn_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6
}

function run_test() {
    # Offloading ICMP with connection tracking is not supported
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($LB_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $LB_IPV4 && success || err "icmp failed"

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($LB_IPV4)"
    check_local_tcp_traffic_offload $LB_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($LB_IPV4)"
    check_local_udp_traffic_offload $LB_IPV4

    # Offloading ICMP with connection tracking is not supported
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($LB_IPV6)"
    ip netns exec $CLIENT_NS ping -w 4 $LB_IPV6 && success || err "icmp6 failed"

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($LB_IPV6)"
    check_local_tcp6_traffic_offload $LB_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($LB_IPV6)"
    check_local_udp6_traffic_offload $LB_IPV6
}

TRAFFIC_INFO['local_traffic']=1

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
