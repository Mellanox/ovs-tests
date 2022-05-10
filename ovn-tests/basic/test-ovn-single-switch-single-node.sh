#!/bin/bash
#
# Test traffic between VFs configured with OVN and OVS then check traffic is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-basic-test.sh

require_interfaces NIC

read_single_switch_topology

function config_test() {
    config_ovn_single_node
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6
    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_icmp_traffic_offload $SERVER_IPV4

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_local_tcp_traffic_offload $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_local_udp_traffic_offload $SERVER_IPV4

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    check_icmp6_traffic_offload $SERVER_IPV6

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_local_tcp6_traffic_offload $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_local_udp6_traffic_offload $SERVER_IPV6
}

TRAFFIC_INFO['local_traffic']=1

ovn_clean_up
trap ovn_clean_up EXIT

config_test
run_test

trap - EXIT
ovn_clean_up

test_done
