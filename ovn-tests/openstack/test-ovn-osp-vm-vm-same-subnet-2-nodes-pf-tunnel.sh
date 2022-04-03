#!/bin/bash
#
# Test traffic VM to VM on same subnet different nodes configured with OSP and OVN then verify traffic is offloaded
#

CONFIG_REMOTE=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-osp-test.sh

require_interfaces NIC
require_remote_server

read_osp_topology_vm_vm_same_subnet
ovn_set_ips

function config_test() {
    ovn_start_northd_central $ovn_central_ip
    ovn_create_topology

    config_ovn_pf $ovn_central_ip $ovn_controller_ip CLIENT_VF CLIENT_REP
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6

    on_remote_exec "config_ovn_pf $ovn_central_ip $ovn_remote_controller_ip SERVER_VF SERVER_REP
                    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6"
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_icmp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_IPV4

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_remote_tcp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_remote_udp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV4

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_icmp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_IPV6

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_remote_tcp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_remote_udp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6
}

ovn_clean_up
trap ovn_clean_up EXIT

config_test
run_test

trap - EXIT
ovn_clean_up

test_done
