#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to pod on different nodes with VF LAG tunnel
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-test.sh

require_interfaces NIC NIC2
require_remote_server

read_k8s_topology_pod_service_different_nodes

nic=$OVN_BOND


function __clean_up_test() {
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    __reset_nic $NIC
    __reset_nic $NIC2
    ovn_remove_network $BRIDGE $nic
    ovs_conf_remove max-idle
    start_clean_openvswitch
    ip -all netns del
    clean_vf_lag
    __reset_nic $NIC
    __reset_nic $NIC2
}

function clean_up_test() {
    __clean_up_test
    on_remote_exec "__clean_up_test"

    ovn_start_clean
    ovn_stop_northd_central
}

function config_test() {
    ovn_start_northd_central $CLIENT_NODE_IP
    ovn_create_topology

    config_ovn_k8s_vf_lag $CLIENT_NODE_IP $CLIENT_NODE_IP $CLIENT_NODE_IP_MASK $CLIENT_NODE_MAC CLIENT_VF CLIENT_REP
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    on_remote_exec "config_ovn_k8s_vf_lag $CLIENT_NODE_IP $SERVER_NODE_IP $SERVER_NODE_IP_MASK $SERVER_NODE_MAC SERVER_VF SERVER_REP
                    ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6"
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    run_remote_traffic "icmp6_is_not_offloaded" "icmp4_is_not_offloaded" $SERVER_VF $LB_IPV4 $LB_IPV6
}

clean_up_test

trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
