#!/bin/bash
#
# Test traffic between VFs on different nodes configured with OVN and OVS then check traffic is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

require_remote_server

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
    ip netns exec ns0 ip -6 addr add $IP_V6_1/124 dev $VF
    on_remote_exec "
    config_vf ns0 $VF $REP $IP2 $MAC2
    ip netns exec ns0 ip -6 addr add $IP_V6_2/124 dev $VF
    "

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

HAS_REMOTE=1

ovn_clean_up

# trap for existing script to clean up
trap ovn_clean_up EXIT

ovn_config
run_test


# Clean up and clear trap
ovn_clean_up
trap - EXIT

test_done
