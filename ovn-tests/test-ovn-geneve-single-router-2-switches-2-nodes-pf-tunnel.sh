#!/bin/bash
#
# Verify traffic between VFs on different nodes configured with OVN router and 2 switches is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

require_remote_server

TOPOLOGY=$TOPOLOGY_SINGLE_ROUTER_2_SWITCHES
SWITCH1=$(ovn_get_switch_name_with_vif_port $TOPOLOGY 0)
SWITCH2=$(ovn_get_switch_name_with_vif_port $TOPOLOGY 1)

IP_GW1=$(ovn_get_switch_gateway_ip $TOPOLOGY $SWITCH1)
IP_GW2=$(ovn_get_switch_gateway_ip $TOPOLOGY $SWITCH2)

IP_V6_GW1=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SWITCH1)
IP_V6_GW2=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SWITCH2)

PORT1=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH1)
MAC1=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH1 $PORT1)
IP1=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH1 $PORT1)
IP_V6_1=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH1 $PORT1)

PORT2=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH2)
MAC2=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH2 $PORT2)
IP2=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH2 $PORT2)
IP_V6_2=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH2 $PORT2)

function config() {
    # Verify NIC
    require_interfaces NIC

    # switchdev mode for NIC
    enable_switchdev
    bind_vfs

    # Verify VFs and REPs
    require_interfaces VF REP

    ifconfig $VF 0 mtu 1300

    # Start OVN
    ifconfig $NIC $OVN_CENTRAL_IP
    start_clean_openvswitch
    ovn_set_ovs_config $OVN_CENTRAL_IP $OVN_CENTRAL_IP $TUNNEL_GENEVE
    ovn_start_northd_central $OVN_CENTRAL_IP
    ovn_start_ovn_controller
}

function config_remote() {
    on_remote_exec "
    # Verify NIC
    require_interfaces NIC

    # switchdev mode for NIC
    enable_switchdev
    bind_vfs

    # Verify VFs and REPs
    require_interfaces VF REP

    # Start OVN
    ifconfig $NIC $OVN_REMOTE_CONTROLLER_IP
    start_clean_openvswitch
    ovn_set_ovs_config $OVN_CENTRAL_IP $OVN_REMOTE_CONTROLLER_IP $TUNNEL_GENEVE
    ovn_start_ovn_controller
    "
}

function pre_test() {
    config
    config_remote
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY_SINGLE_ROUTER_2_SWITCHES

    # Add REP to OVS
    ovs_add_port_to_switch $OVN_BRIDGE_INT $REP
    on_remote_exec "ovs_add_port_to_switch $OVN_BRIDGE_INT $REP"

    ovs-vsctl show

    # Bind OVS ports to OVN
    ovn_bind_ovs_port $REP $PORT1
    on_remote_exec "ovn_bind_ovs_port $REP $PORT2"

    ovn-sbctl show

    # Move VFs to namespaces and set MACs and IPS
    config_vf ns0 $VF $REP $IP1 $MAC1
    ip netns exec ns0 ip route add default via $IP_GW1 dev $VF
    ip netns exec ns0 ip -6 addr add $IP_V6_1/124 dev $VF
    ip netns exec ns0 ip -6 route add default via $IP_V6_GW1 dev $VF

    on_remote_exec "
    config_vf ns0 $VF $REP $IP2 $MAC2
    ip netns exec ns0 ip route add default via $IP_GW2 dev $VF
    ip netns exec ns0 ip -6 addr add $IP_V6_2/124 dev $VF
    ip netns exec ns0 ip -6 route add default via $IP_V6_GW2 dev $VF
    "

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_remote_tcp_traffic_offload $REP ns0 ns0 $IP2

    title "Test UDP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_remote_udp_traffic_offload $REP ns0 ns0 $IP2

    # ICMP6 offloading is not supported because IPv6 packet header doesn't contain checksum header
    # which cause offloading to fail
    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2)"
    ip netns exec ns0 ping -6 -w 4 $IP_V6_2 && success || err

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_remote_tcp6_traffic_offload $REP ns0 ns0 $IP_V6_2

    title "Test UDP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_remote_udp6_traffic_offload $REP ns0 ns0 $IP_V6_2
}

HAS_REMOTE=1

ovn_clean_up

trap ovn_clean_up EXIT

pre_test
run_test


ovn_clean_up
trap - EXIT

test_done
