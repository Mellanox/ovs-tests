#!/bin/bash
#
# Test ICMP and TCP traffics between VFs configured with OVN and OVS then check traffic is offloaded
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

TCPDUMP_FILE=/tmp/$$.pcap

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

    # Remove IPs from VFs
    for i in $VF $VF2; do
        ip addr flush dev $i
        ip -6 addr flush dev $i
    done

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
    ovn_start_northd_central $OVN_LOCAL_CENTRAL_IP
    ovn_start_ovn_controller
    ovn_set_ovs_config $OVN_SYSTEM_ID $OVN_LOCAL_CENTRAL_IP $OVN_LOCAL_CENTRAL_IP $TUNNEL_GENEVE
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

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    sleep 2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_local_tcp_traffic_offload $REP ns0 ns1 $IP2

    sleep 2

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_icmp6_traffic_offload $REP ns0 $IP_V6_2

    sleep 2

    title "Test TCP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_local_tcp6_traffic_offload $REP ns0 ns1 $IP_V6_2

}

cleanup
pre_test

# trap for existing script to clean up
trap cleanup EXIT

start_check_syndrome
run_test

check_syndrome

test_done
