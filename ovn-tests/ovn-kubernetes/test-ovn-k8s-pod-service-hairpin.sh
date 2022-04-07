#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to service hairpin (sender is receiver)
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-test.sh

require_interfaces NIC

read_k8s_topology_pod_service_hairpin

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
}

function config_test() {
    config_ovn_k8s_hairpin
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    # Offloading ICMP with connection tracking is not supported and offloading loopback traffic is not supported
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($LB_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $LB_IPV4 && success || err

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $CLIENT_VF($LB_IPV4) offloaded"
    check_local_tcp_traffic_offload $CLIENT_REP $CLIENT_NS $CLIENT_NS $LB_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $CLIENT_VF($LB_IPV4) offloaded"
    check_local_udp_traffic_offload $CLIENT_REP $CLIENT_NS $CLIENT_NS $LB_IPV4

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail and offloading ICMP with connection tracking is not supported
    # and offloading loopback traffic is not supported
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($LB_IPV6)"
    ip netns exec $CLIENT_NS ping -6 -w 4 $LB_IPV6 && success || err

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $CLIENT_VF($LB_IPV6) offloaded"
    check_local_tcp6_traffic_offload $CLIENT_REP $CLIENT_NS $CLIENT_NS $LB_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $CLIENT_VF($LB_IPV6) offloaded"
    check_local_udp6_traffic_offload $CLIENT_REP $CLIENT_NS $CLIENT_NS $LB_IPV6
}

clean_up_test

trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
