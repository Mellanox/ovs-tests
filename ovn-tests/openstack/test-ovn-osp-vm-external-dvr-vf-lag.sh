#!/bin/bash
#
# Test traffic VM to external with DVR (external gateway same as host) configured with VF LAG
#

HAS_BOND=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-osp-test.sh

require_interfaces NIC NIC2
require_remote_server

read_osp_topology_vm_ext

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
    on_remote_exec "clean_vf_lag
                    __reset_nic"
}

function config_test() {
    config_ovn_single_node_external_vf_lag "balance-xor" $OVN_LOCAL_CENTRAL_IP $OSP_EXTERNAL_NETWORK
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    config_ovn_external_server_vf_lag_ip "balance-xor"
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    # Offloading ICMP with connection tracking is not supported
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV4 && success || err

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_remote_tcp_traffic_offload $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_remote_udp_traffic_offload $SERVER_IPV4

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -6 -w 4 $SERVER_IPV6 && success || err

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_remote_tcp6_traffic_offload $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_remote_udp6_traffic_offload $SERVER_IPV6
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
