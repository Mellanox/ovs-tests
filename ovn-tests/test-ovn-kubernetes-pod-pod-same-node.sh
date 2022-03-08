#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to pod on single node
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh
. $my_dir/common-ovn-kubernetes.sh

read_k8s_topology_pod_pod_same_node

nic=$NIC
BRIDGE=$(nic_to_bridge $nic)

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
}

function config_test() {
    ovn_config_interfaces
    start_clean_openvswitch

    ip link set $nic up
    ip link set $nic addr $CLIENT_NODE_MAC
    ovn_add_network $BRIDGE $nic $OVN_KUBERNETES_NETWORK
    ip addr add $CLIENT_NODE_IP/$CLIENT_NODE_IP_MASK dev $BRIDGE

    ovn_set_ovs_config $CLIENT_NODE_IP $CLIENT_NODE_IP
    ovn_start_ovn_controller
    ovs_conf_set max-idle 20000

    __ovn_config_mtu

    ovn_start_northd_central $CLIENT_NODE_IP
    ovn_create_topology

    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_icmp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_IPV4

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_local_tcp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($SERVER_IPV4) offloaded"
    check_local_udp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV4

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    check_icmp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_IPV6

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_local_tcp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_local_udp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6
}

clean_up_test

trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
