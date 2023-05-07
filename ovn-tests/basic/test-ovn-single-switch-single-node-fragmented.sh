#!/bin/bash
#
# Test fragmented traffic between VFs configured with OVN and OVS then check traffic is not offloaded
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

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4)"
    check_fragmented_ipv4_traffic $CLIENT_REP $CLIENT_NS $SERVER_IPV4 2000

    if [ -n "$IGNORE_IPV6_TRAFFIC" ]; then
        warn "$IGNORE_IPV6_TRAFFIC"
        return
    fi

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    check_fragmented_ipv6_traffic $CLIENT_REP $CLIENT_NS $SERVER_IPV6 2000
}

TRAFFIC_INFO['local_traffic']=1

ovn_clean_up
trap ovn_clean_up EXIT

config_test
run_test

trap - EXIT
ovn_clean_up

test_done
