#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to pod on 2 nodes with VLAN with bluefield
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-bf-test.sh

require_interfaces NIC
require_remote_server

read_k8s_topology_pod_pod_different_nodes

BRIDGE=$(nic_to_bridge $BF_NIC)

function clean_up_test() {
    ip -all netns del
    config_sriov 0
    on_bf_exec "ovn_start_clean
                ovn_stop_ovn_controller
                start_clean_openvswitch
                ovn_stop_northd_central
                __reset_nic $BF_NIC"

    on_remote_exec "ip -all netns del
               config_sriov 0"
    on_bf_exec "ovn_stop_ovn_controller
               start_clean_openvswitch
               __reset_nic $BF_NIC"
}

function config_test() {
    config_sriov
    require_interfaces CLIENT_VF
    on_bf_exec "ovn_start_northd_central $CLIENT_NODE_IP
                ovn_create_topology
                config_bf_ovn_pf_vlan $CLIENT_NODE_IP $CLIENT_NODE_IP $CLIENT_NODE_IP_MASK $CLIENT_NODE_MAC $OVN_K8S_VLAN_NODE1_TUNNEL_IP"
    config_bf_ovn_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    on_remote_exec "config_sriov
                    require_interfaces SERVER_VF"
    on_remote_bf_exec "config_bf_ovn_pf_vlan $CLIENT_NODE_IP $SERVER_NODE_IP $SERVER_NODE_IP_MASK $SERVER_NODE_MAC $OVN_K8S_VLAN_NODE2_TUNNEL_IP"
    config_bf_ovn_remote_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6
}

function run_test() {
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV4 && success || err "icmp failed"

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV6 && success || err "icmp6 failed"
}

clean_up_test
trap clean_up_test EXIT

config_test
run_test
trap - EXIT
clean_up_test

test_done
