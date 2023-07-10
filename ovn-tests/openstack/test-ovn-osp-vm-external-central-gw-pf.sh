#!/bin/bash
#
# Test traffic VM to external with central gateway chassis
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-osp-test.sh

require_interfaces NIC
require_remote_server

read_osp_topology_vm_ext_snat
ovn_set_ips

SERVER_PORT=$NIC
export GW_CHASSIS=$(on_remote_exec "get_ovs_id")

function clean_up_test() {
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    start_clean_openvswitch
    ip -all netns del
    config_sriov 0
    __reset_nic $NIC

    on_remote_exec "ovn_stop_ovn_controller
                    ovn_remove_ovs_config
                    ovn_remove_network $BRIDGE $NIC
                    start_clean_openvswitch
                    __reset_nic $NIC"

    ovn_start_clean
    ovn_stop_northd_central
}

function config_test() {
    ovn_start_northd_central $ovn_central_ip
    ovn_create_topology

    config_ovn_pf $ovn_central_ip $ovn_controller_ip CLIENT_VF CLIENT_REP
    config_port_ip $NIC $SERVER_IPV4 $SERVER_IPV6

    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    on_remote_exec "config_ovn_osp_gw_chassis_pf $ovn_central_ip $ovn_remote_controller_ip"
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    # Offloading ICMP with connection tracking is not supported
    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4)"
    ip netns exec $CLIENT_NS ping -w 4 $SERVER_IPV4 && success || err

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_local_tcp_traffic_offload $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_local_udp_traffic_offload $SERVER_IPV4

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -6 -w 4 $SERVER_IPV6 && success || err

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_local_tcp6_traffic_offload $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_local_udp6_traffic_offload $SERVER_IPV6
}

TRAFFIC_INFO['server_ns']=""
TRAFFIC_INFO['server_verify_offload']=""
TRAFFIC_INFO['local_traffic']=1

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
