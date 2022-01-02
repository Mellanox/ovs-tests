#!/bin/bash
#
# Test traffic between VFs on different nodes configured with OVN and OVS with VF LAG and VLAN then check traffic is offloaded
#

CONFIG_REMOTE=1
HAS_BOND=1
HAS_VLAN=1

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

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
    on_remote_exec "ovn_config_interface_namespace $VF $REP ns0 $PORT2 $MAC2 $IP2 $IP_V6_2"

    ovs-vsctl show
    ovn-sbctl show

    title "Test ICMP traffic between $VF($IP1) -> $VF($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    title "Test TCP traffic between $VF($IP1) -> $VF($IP2) offloaded"
    check_remote_tcp_traffic_offload $REP ns0 ns0 $IP2

    title "Test UDP traffic between $VF($IP1) -> $VF($IP2) offloaded"
    check_remote_udp_traffic_offload $REP ns0 ns0 $IP2

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF($IP_V6_2) offloaded"
    check_icmp6_traffic_offload $REP ns0 $IP_V6_2

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $VF($IP_V6_2) offloaded"
    check_remote_tcp6_traffic_offload $REP ns0 ns0 $IP_V6_2

    title "Test UDP6 traffic between $VF($IP_V6_1) -> $VF($IP_V6_2) offloaded"
    check_remote_udp6_traffic_offload $REP ns0 ns0 $IP_V6_2
}

ovn_execute_test
