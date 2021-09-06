#!/bin/bash
#
# Verify traffic between VFs configured with OVN router and 2 switches is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-ovn.sh

require_ovn

# IPs and MACs
IP_GW1="7.7.7.1"
IP_GW2="7.7.8.1"

IP1="7.7.7.2"
IP2="7.7.8.2"

MAC1="50:54:00:00:00:01"
MAC2="50:54:00:00:00:02"

# Ports
PORT1="sw0-port1"
PORT2="sw1-port1"

# stop OVN, clean namespaces, ovn network topology, and ovs br-int interfaces
function cleanup() {
    # Remove OVN topology
    ovn_destroy_topology $TOPOLOGY_SINGLE_ROUTER_2_SWITCHES

    # Stop ovn
    ovn_remove_ovs_config
    ovn_stop_ovn_controller
    ovn_stop_northd_central

    # Clean namespaces
    ip -all netns del

    unbind_vfs
    bind_vfs

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
    ovn_start_northd_central
    ovn_start_ovn_controller
    ovn_set_ovs_config
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY_SINGLE_ROUTER_2_SWITCHES

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
    ip netns exec ns0 ip route add default via $IP_GW1 dev $VF

    config_vf ns1 $VF2 $REP2 $IP2 $MAC2
    ip netns exec ns1 ip route add default via $IP_GW2 dev $VF2

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    sleep 2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_tcp_traffic_offload $REP ns0 ns1 $IP2

    sleep 2

    title "Test UDP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_udp_traffic_offload $REP ns0 ns1 $IP2
}

cleanup

trap cleanup EXIT

pre_test
start_check_syndrome
run_test

check_syndrome

cleanup
trap - EXIT

test_done
