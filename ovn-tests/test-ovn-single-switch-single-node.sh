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

# stop OVN, clean namespaces, ovn network topology, and ovs br-int interfaces
function cleanup() {
    # Remove OVN topology
    ovn_destroy_topology $TOPOLOGY

    # Stop ovn
    ovn_remove_ovs_config
    ovn_stop_ovn_controller
    ovn_stop_northd_central

    # Clean namespaces
    ip -all netns del

    unbind_vfs
    bind_vfs

    # Clean ovs br-int
    ovs_clear_bridges
}

function pre_test() {
    # Verify NIC
    require_interfaces NIC

    # switchdev mode for NIC
    enable_switchdev
    bind_vfs

    # Verify VFs and REPs
    require_interfaces VF VF2 REP REP2

    # Start OVN
    start_clean_openvswitch
    ovn_set_ovs_config
    ovn_start_northd_central
    ovn_start_ovn_controller
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY

    # Add REP to OVS
    ovs_add_port_to_switch $OVN_BRIDGE_INT $REP
    ovs_add_port_to_switch $OVN_BRIDGE_INT $REP2

    ovs-vsctl show

    # Bind OVS ports to OVN
    ovn_bind_ovs_port $REP $PORT1
    ovn_bind_ovs_port $REP2 $PORT2

    ovn-sbctl show

    # Move VFs to namespaces and set MACs and IPS
    config_vf ns0 $VF $REP $IP1 $MAC1
    ip netns exec ns0 ip -6 addr add $IP_V6_1/124 dev $VF
    config_vf ns1 $VF2 $REP2 $IP2 $MAC2
    ip netns exec ns1 ip -6 addr add $IP_V6_2/124 dev $VF2

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

cleanup

# trap for existing script to clean up
trap cleanup EXIT

pre_test
start_check_syndrome
run_test

check_syndrome

# Clean up and clear trap
cleanup
trap - EXIT

test_done
