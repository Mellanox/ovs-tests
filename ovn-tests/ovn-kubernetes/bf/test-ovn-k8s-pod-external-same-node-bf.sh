#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to external on same node is offloaded with bluefield
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-bf-test.sh

require_interfaces NIC

read_k8s_topology_pod_ext
SERVER_IPV4=$EXTERNAL_SERVER_IP

BRIDGE=$(nic_to_bridge $BF_NIC)

function clean_up_test() {
    ip -all netns del
    ip addr flush dev $NIC
    config_sriov 0
    on_bf_exec "ovn_stop_ovn_controller
                ovn_remove_ovs_config
                ovn_remove_network $BRIDGE $BF_NIC
                start_clean_openvswitch
                __reset_nic $BF_NIC
                ovn_start_clean
                ovn_stop_northd_central"
}

function config_test() {
    config_sriov
    require_interfaces CLIENT_VF
    ip addr add $EXTERNAL_SERVER_IP/$SERVER_NODE_IP_MASK dev $NIC

    on_bf_exec "ovn_start_northd_central $CLIENT_NODE_IP
                ovn_create_topology
                config_bf_ovn_k8s_pf $CLIENT_NODE_IP $CLIENT_NODE_IP $CLIENT_NODE_IP_MASK $CLIENT_NODE_MAC
                ovs-vsctl add-port $BRIDGE $BF_HOST_NIC
                ip link set $BF_HOST_NIC up"

    config_bf_ovn_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
}

function run_test() {
    # Offloading ICMP with connection tracking is not supported
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $NIC($SERVER_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV4 && success || err

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $NIC($SERVER_IPV4) offloaded"
    check_local_tcp_traffic_offload $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $NIC($SERVER_IPV4) offloaded"
    check_local_udp_traffic_offload $SERVER_IPV4
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
