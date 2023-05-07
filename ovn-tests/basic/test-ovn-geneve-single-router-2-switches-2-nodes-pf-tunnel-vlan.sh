#!/bin/bash
#
# Verify traffic between VFs on different nodes configured with OVN router and 2 switches and OVS VLAN is offloaded
#

CONFIG_REMOTE=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-basic-test.sh

min_nic_cx6dx
require_remote_server

require_interfaces NIC
read_single_router_two_switches_topology
ovn_set_ips

function config_test() {
    ovn_start_northd_central $ovn_central_ip
    ovn_create_topology

    config_ovn_pf_vlan $ovn_central_ip $ovn_controller_ip CLIENT_VF CLIENT_REP
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    on_remote_exec "config_ovn_pf_vlan $ovn_central_ip $ovn_remote_controller_ip SERVER_VF SERVER_REP
                    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6"
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    WA_dpdk_initial_ping_and_flush
    run_remote_traffic "icmp6_is_not_offloaded"
}

ovn_clean_up
trap ovn_clean_up EXIT

config_test
run_test

trap - EXIT
ovn_clean_up

test_done
