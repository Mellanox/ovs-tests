#!/bin/bash
#
# Verify traffic for OVN-Kubernetes pod to pod on different nodes with VF LAG tunnel
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh
. $my_dir/common-ovn-kubernetes.sh

require_interfaces NIC
require_remote_server

CLIENT_SWITCH=$NODE1_SWITCH
CLIENT_PORT=$NODE1_SWITCH_PORT1
CLIENT_NODE_ROUTER=$NODE1_ROUTER
CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
CLIENT_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $CLIENT_SWITCH)
CLIENT_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $CLIENT_SWITCH)
CLIENT_NODE_MAC=$(ovn_get_router_port_mac $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
CLIENT_NODE_IP=$(ovn_get_router_port_ip $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
CLIENT_NODE_IP_MASK=$(ovn_get_router_port_ip_mask $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
CLIENT_NS=ns0
CLIENT_VF=$VF
CLIENT_REP=$REP

SERVER_SWITCH=$NODE2_SWITCH
SERVER_PORT=$NODE2_SWITCH_PORT1
SERVER_NODE_ROUTER=$NODE2_ROUTER
SERVER_NODE_PORT=$NODE2_ROUTER_PORT
SERVER_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
SERVER_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
SERVER_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
SERVER_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $SERVER_SWITCH)
SERVER_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SERVER_SWITCH)
SERVER_NODE_MAC=$(ovn_get_router_port_mac $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
SERVER_NODE_IP=$(ovn_get_router_port_ip $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
SERVER_NODE_IP_MASK=$(ovn_get_router_port_ip_mask $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
SERVER_NS=ns0
SERVER_VF=$VF
SERVER_REP=$REP

nic=$OVN_BOND
BRIDGE=$(nic_to_bridge $nic)
HAS_BOND=1

function clean_up_test() {
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    __reset_nic $NIC
    __reset_nic $NIC2
    ovn_remove_network $BRIDGE $nic
    ovs_conf_remove max-idle
    start_clean_openvswitch
    clear_bonding
    config_sriov 0 $NIC
    config_sriov 0 $NIC2

    on_remote_exec "ovn_stop_ovn_controller
                    ovn_remove_ovs_config
                    __reset_nic $NIC
                    __reset_nic $NIC2
                    ovn_remove_network $BRIDGE $nic
                    ovs_conf_remove max-idle
                    start_clean_openvswitch
                    clear_bonding
                    config_sriov 0 $NIC
                    config_sriov 0 $NIC2"

    ovn_start_clean
    ovn_stop_northd_central
}

function config_test() {
    ovn_start_northd_central $CLIENT_NODE_IP
    ovn_create_topology

    ovn_config_interfaces
    start_clean_openvswitch
    ovs_conf_set max-idle 20000
    ovn_add_network $BRIDGE $nic $OVN_KUBERNETES_NETWORK
    ip link set $NIC up
    ip link set $NIC mtu $OVN_TUNNEL_MTU
    ip link set $NIC2 up
    ip link set $NIC2 mtu $OVN_TUNNEL_MTU
    ip link set $nic up
    ip link set $nic mtu $OVN_TUNNEL_MTU
    ip link set $nic addr $CLIENT_NODE_MAC
    ip link set $BRIDGE up
    ip link set $BRIDGE mtu $OVN_TUNNEL_MTU
    ip addr add $CLIENT_NODE_IP/$CLIENT_NODE_IP_MASK dev $BRIDGE
    ovn_set_ovs_config $CLIENT_NODE_IP $CLIENT_NODE_IP
    ovn_start_ovn_controller

    on_remote_exec "ovn_config_interfaces
                    start_clean_openvswitch
                    ovs_conf_set max-idle 20000
                    ovn_add_network $BRIDGE $nic $OVN_KUBERNETES_NETWORK
                    ip link set $NIC up
                    ip link set $NIC mtu $OVN_TUNNEL_MTU
                    ip link set $NIC2 up
                    ip link set $NIC2 mtu $OVN_TUNNEL_MTU
                    ip link set $nic up
                    ip link set $nic mtu $OVN_TUNNEL_MTU
                    ip link set $nic addr $SERVER_NODE_MAC
                    ip link set $BRIDGE up
                    ip link set $BRIDGE mtu $OVN_TUNNEL_MTU
                    ip addr add $SERVER_NODE_IP/$SERVER_NODE_IP_MASK dev $BRIDGE
                    ovn_set_ovs_config $CLIENT_NODE_IP $SERVER_NODE_IP
                    ovn_start_ovn_controller"

    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6
    on_remote_exec "ovn_config_interface_namespace $SERVER_VF $SERVER_REP $SERVER_NS $SERVER_PORT $SERVER_MAC $SERVER_IPV4 $SERVER_IPV6 $SERVER_GATEWAY_IPV4 $SERVER_GATEWAY_IPV6"
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

    #ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -6 -w 4 $SERVER_IPV6 && success || err

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_remote_tcp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_VF($SERVER_IPV6) offloaded"
    check_remote_udp6_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_NS $SERVER_IPV6
}

clean_up_test

trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
