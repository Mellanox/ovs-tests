#!/bin/bash
#
# Test fragmented traffic between VFs configured with OVN and OVS then check traffic is not offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-ovn.sh

require_ovn

# IPs and MACs
IP1="7.7.7.1"
IP2="7.7.7.2"

IP_V6_1="7:7:7::1"
IP_V6_2="7:7:7::2"

MAC1="50:54:00:00:00:01"
MAC2="50:54:00:00:00:02"

# Ports
PORT1="sw0-port1"
PORT2="sw0-port2"

# stop OVN, clean namespaces, ovn network topology, and ovs br-int interfaces
function cleanup() {
    # Remove OVN topology
    ovn_destroy_topology $TOPOLOGY_SINGLE_SWITCH

    # Stop ovn
    ovn_remove_ovs_config
    ovn_stop_ovn_controller
    ovn_stop_northd_central

    # Clean namespaces
    ip netns del ns0 2>/dev/null
    ip netns del ns1 2>/dev/null

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
    ovn_start_northd_central
    ovn_start_ovn_controller
    ovn_set_ovs_config
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY_SINGLE_SWITCH

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

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2)"
    check_fragmented_ipv4_traffic $REP ns0 $IP2 1500

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2)"
    check_fragmented_ipv6_traffic $REP ns0 $IP_V6_2 1500
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
