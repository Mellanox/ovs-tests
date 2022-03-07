#!/bin/bash
#
# Test fragmented traffic between VFs on different nodes configured with OVN and OVS then check traffic is not offloaded
#

CONFIG_REMOTE=1
IS_FRAGMENTED=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

read_single_switch_topology

function run_test() {
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6
    on_remote_exec "ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6"

    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4)"
    check_fragmented_ipv4_traffic $CLIENT_REP $CLIENT_NS $SERVER_IPV4 1500

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    check_fragmented_ipv6_traffic $CLIENT_REP $CLIENT_NS $SERVER_IPV6 1500
}

ovn_execute_test
