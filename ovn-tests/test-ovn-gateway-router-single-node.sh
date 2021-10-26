#!/bin/bash
#
# Verify traffic between VF and underlay configured with OVN gateway router is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

require_remote_server

TOPOLOGY=$TOPOLOGY_GATEWAY_ROUTER
EXT_GW_ROUTER="gw0"
EXT_GW_PORT="gw0-outside"
SWITCH="sw0"

IP_EXT_GW=$(ovn_get_router_port_ip $TOPOLOGY $EXT_GW_ROUTER $EXT_GW_PORT)
IP_GW=$(ovn_get_switch_gateway_ip $TOPOLOGY $SWITCH)

IP_V6_EXT_GW=$(ovn_get_router_port_ipv6 $TOPOLOGY $EXT_GW_ROUTER $EXT_GW_PORT)
IP_V6_GW=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SWITCH)

PORT=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH)
MAC=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH $PORT)
IP=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH $PORT)
IP_V6_1=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH $PORT)

IP2=$OVN_EXTERNAL_NETWORK_HOST_IP
IP_V6_2=$OVN_EXTERNAL_NETWORK_HOST_IP_V6

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
    ip addr flush dev $NIC
    ip -6 route del $IP_V6_1 via $IP_V6_EXT_GW dev $NIC
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
    ifconfig $NIC $IP2/24
    ip -6 addr add $IP_V6_2/124 dev $NIC

    ip route add $IP via $IP_EXT_GW dev $NIC
    ip -6 route add $IP_V6_1 via $IP_V6_EXT_GW dev $NIC

    add_name_for_default_network_namespace
    "
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY

    # Add REP to OVS
    ovs_add_port_to_switch $OVN_BRIDGE_INT $REP

    ovs-vsctl show

    # Bind OVS ports to OVN
    ovn_bind_ovs_port $REP $PORT

    ovn-sbctl show

    # Move VFs to namespaces and set MACs and IPS
    config_vf ns0 $VF $REP $IP $MAC
    ip netns exec ns0 ip route add default via $IP_GW dev $VF
    ip netns exec ns0 ip -6 addr add $IP_V6_1/124 dev $VF
    ip netns exec ns0 ip -6 route add default via $IP_V6_GW dev $VF

    title "Test ICMP traffic between $VF($IP) -> $NIC($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    title "Test TCP traffic between $VF($IP) -> $NIC($IP2) offloaded"
    check_remote_tcp_traffic_offload $REP ns0 "" $IP2

    title "Test UDP traffic between $VF($IP) -> $NIC($IP2) offloaded"
    check_remote_udp_traffic_offload $REP ns0 "" $IP2

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $NIC($IP_V6_2)"
    ip netns exec ns0 ping -6 -w 4 $IP_V6_2 && success || err

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $NIC($IP_V6_2) offloaded"
    check_remote_tcp6_traffic_offload $REP ns0 "" $IP_V6_2

    title "Test UDP6 traffic between $VF($IP_V6_1) -> $NIC($IP_V6_2) offloaded"
    check_remote_udp6_traffic_offload $REP ns0 "" $IP_V6_2
}

cleanup

trap cleanup EXIT

pre_test
run_test

cleanup
trap - EXIT

test_done
