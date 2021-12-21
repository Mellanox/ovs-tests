#!/bin/bash
#
# Test traffic between VFs configured with OVN and OVS then check traffic is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

TOPOLOGY=$TOPOLOGY_SINGLE_SWITCH
SWITCH=$(ovn_get_switch_name_with_vif_port $TOPOLOGY)

PORT1=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH 0)
MAC1=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH $PORT1)
IP1=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH $PORT1)
IP_V6_1=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH $PORT1)

PORT2=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH 1)
MAC2=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH $PORT2)
IP2=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH $PORT2)
IP_V6_2=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH $PORT2)

function run_test() {
    ovn_config_interface_namespace $VF $REP ns0 $PORT1 $MAC1 $IP1 $IP_V6_1
    ovn_config_interface_namespace $VF2 $REP2 ns1 $PORT2 $MAC2 $IP2 $IP_V6_2

    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_tcp_traffic_offload $REP ns0 ns1 $IP2

    title "Test UDP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_udp_traffic_offload $REP ns0 ns1 $IP2

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_icmp6_traffic_offload $REP ns0 $IP_V6_2

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_local_tcp6_traffic_offload $REP ns0 ns1 $IP_V6_2

    title "Test UDP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_local_udp6_traffic_offload $REP ns0 ns1 $IP_V6_2
}

ovn_execute_test
