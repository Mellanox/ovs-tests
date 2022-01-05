#!/bin/bash
#
# Verify traffic between VF and underlay configured with OVN gateway router is offloaded
#

HAS_REMOTE=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

TOPOLOGY=$TOPOLOGY_GATEWAY_ROUTER

CLIENT_SWITCH=$SWITCH1
CLIENT_PORT=$SWITCH1_PORT1
CLIENT_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
CLIENT_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $CLIENT_SWITCH)
CLIENT_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $CLIENT_SWITCH)
CLIENT_NS=ns0
CLIENT_VF=$VF
CLIENT_REP=$REP

SERVER_ROUTER=$GATEWAY_ROUTER
SERVER_ROUTER_PORT=$GATEWAY_ROUTER_PORT
SERVER_IPV4=$OVN_EXTERNAL_NETWORK_HOST_IP
SERVER_IPV6=$OVN_EXTERNAL_NETWORK_HOST_IP_V6
SERVER_GATEWAY_IPV4=$(ovn_get_router_port_ip $TOPOLOGY $SERVER_ROUTER $SERVER_ROUTER_PORT)
SERVER_GATEWAY_IPV6=$(ovn_get_router_port_ipv6 $TOPOLOGY $SERVER_ROUTER $SERVER_ROUTER_PORT)
SERVER_PORT=$NIC

# stop OVN, clean namespaces, ovn network topology, and ovs br-int interfaces
function cleanup() {
    # Remove OVN topology
    ovn_destroy_topology $TOPOLOGY

    # Stop ovn
    ovn_stop_ovn_controller
    ovn_stop_northd_central
    ovn_remove_ovs_config

    # Clean namespaces
    ip -all netns del

    unbind_vfs
    bind_vfs

    ovn_remove_network
    ovs_clear_bridges

    on_remote_exec "
    ip addr flush dev $SERVER_PORT
    ip -6 route del $CLIENT_IPV6 via $SERVER_GATEWAY_IPV6 dev $SERVER_PORT
    ip -all netns del
    "
}

function pre_test() {
    # Verify NIC
    require_interfaces NIC

    # switchdev mode for NIC
    config_sriov 2
    enable_switchdev
    bind_vfs

    # Verify VFs and REPs
    require_interfaces VF REP

    # Start OVN
    start_clean_openvswitch
    ovn_set_ovs_config
    ovn_start_northd_central
    ovn_start_ovn_controller

    ovn_add_network

    on_remote_exec "
    # Verify NIC
    require_interfaces NIC
    ifconfig $SERVER_PORT $SERVER_IPV4/24
    ip -6 addr add $SERVER_IPV6/124 dev $SERVER_PORT

    ip route add $CLIENT_IPV4 via $SERVER_GATEWAY_IPV4 dev $SERVER_PORT
    ip -6 route add $CLIENT_IPV6 via $SERVER_GATEWAY_IPV6 dev $SERVER_PORT

    add_name_for_default_network_namespace
    "
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY

    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_icmp_traffic_offload $CLIENT_REP $CLIENT_NS $SERVER_IPV4

    title "Test TCP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_remote_tcp_traffic_offload $CLIENT_REP $CLIENT_NS "" $SERVER_IPV4

    title "Test UDP traffic between $CLIENT_VF($CLIENT_IPV4) -> $SERVER_PORT($SERVER_IPV4) offloaded"
    check_remote_udp_traffic_offload $CLIENT_REP $CLIENT_NS "" $SERVER_IPV4

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6)"
    ip netns exec $CLIENT_NS ping -6 -w 4 $SERVER_IPV6 && success || err

    title "Test TCP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_remote_tcp6_traffic_offload $CLIENT_REP $CLIENT_NS "" $SERVER_IPV6

    title "Test UDP6 traffic between $CLIENT_VF($CLIENT_IPV6) -> $SERVER_PORT($SERVER_IPV6) offloaded"
    check_remote_udp6_traffic_offload $CLIENT_REP $CLIENT_NS "" $SERVER_IPV6
}

cleanup

trap cleanup EXIT

pre_test
run_test

cleanup
trap - EXIT

test_done
