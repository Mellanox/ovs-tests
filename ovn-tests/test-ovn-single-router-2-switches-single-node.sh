#!/bin/bash
#
# Verify traffic between VFs configured with OVN router and 2 switches is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

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

function run_test() {
    ovn_config_interface_namespace $VF $REP ns0 $PORT1 $MAC1 $IP1 $IP_V6_1 $IP_GW1 $IP_V6_GW1
    ovn_config_interface_namespace $VF2 $REP2 ns1 $PORT2 $MAC2 $IP2 $IP_V6_2 $IP_GW2 $IP_V6_GW2

    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_tcp_traffic_offload $REP ns0 ns1 $IP2

    title "Test UDP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_udp_traffic_offload $REP ns0 ns1 $IP2

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2)"
    ip netns exec ns0 ping -6 -w 4 $IP_V6_2 && success || err

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_local_tcp6_traffic_offload $REP ns0 ns1 $IP_V6_2

    title "Test UDP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_local_udp6_traffic_offload $REP ns0 ns1 $IP_V6_2
}

ovn_clean_up

trap ovn_clean_up EXIT

ovn_config
run_test

ovn_clean_up
trap - EXIT

test_done
