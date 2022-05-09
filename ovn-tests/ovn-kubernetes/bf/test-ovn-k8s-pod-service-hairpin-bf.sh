#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to service hairpin with bluefield
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-k8s-bf-test.sh

require_interfaces NIC

read_k8s_topology_pod_service_hairpin

function clean_up_test() {
    ip -all netns del
    on_bf_exec "ovn_stop_ovn_controller
                start_clean_openvswitch
                ovn_start_clean
                ovn_stop_northd_central"
}

function config_test() {
    config_sriov
    require_interfaces CLIENT_VF
    on_bf_exec "ovn_start_northd_central
                ovn_create_topology
                start_clean_openvswitch
                ovn_set_ovs_config $OVN_LOCAL_CENTRAL_IP $OVN_LOCAL_CENTRAL_IP
                ovn_start_ovn_controller"

    config_bf_ovn_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
}

function run_test() {
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_VF($LB_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $LB_IPV4 && success || err "icmp failed"

    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($LB_IPV6)"
    ip netns exec $CLIENT_NS ping -w 4 $LB_IPV6 && success || err "icmp6 failed"
}

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
