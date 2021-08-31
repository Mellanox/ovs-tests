#!/bin/bash
#
# Test traffic between VFs on different nodes configured with OVN and OVS with VF LAG then check traffic is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-ovn.sh

require_remote_server
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

OVN_REMOTE_SYSTEM_ID=$(get_remote_hostname)

# stop OVN, clean namespaces, ovn network topology, and ovs br-int interfaces
function cleanup() {
    ovn_destroy_topology $TOPOLOGY_SINGLE_SWITCH

    ovn_remove_ovs_config
    ovn_stop_ovn_controller
    ovn_stop_northd_central

    ip netns del ns0 2>/dev/null

    unbind_vfs
    unbind_vfs $NIC2
    clear_bonding $NIC $NIC2
    bind_vfs
    config_sriov 0 $NIC2

    ovs_clear_bridges

    # Clean up on remote
    on_remote_exec "
    ovn_remove_ovs_config
    ovn_stop_ovn_controller

    ip netns del ns0 2>/dev/null

    unbind_vfs
    unbind_vfs $NIC2
    clear_bonding $NIC $NIC2
    bind_vfs
    config_sriov 0 $NIC2

    ovs_clear_bridges
    "
}

function config() {
    # Verify NIC
    require_interfaces NIC NIC2
    config_sriov 0
    config_sriov 0 $NIC2

    config_sriov 2
    config_sriov 2 $NIC2

    enable_switchdev
    enable_switchdev $NIC2
    unbind_vfs
    unbind_vfs $NIC2
    config_bonding $NIC $NIC2 802.3ad
    bind_vfs
    bind_vfs $NIC2

    require_interfaces VF REP

    ifconfig $VF 0 mtu 1300

    # Start OVN
    ifconfig $OVN_BOND $OVN_CENTRAL_IP
    ovn_start_northd_central $OVN_CENTRAL_IP
    ovn_start_ovn_controller
    ovn_set_ovs_config $OVN_SYSTEM_ID $OVN_CENTRAL_IP $OVN_CENTRAL_IP $TUNNEL_GENEVE
}

function config_remote() {
    on_remote_exec "
    # Verify NIC
    require_interfaces NIC NIC2

    config_sriov 0
    config_sriov 0 $NIC2

    config_sriov 2
    config_sriov 2 $NIC2

    enable_switchdev
    enable_switchdev $NIC2
    unbind_vfs
    unbind_vfs $NIC2
    "

    config_remote_bonding $NIC $NIC2 802.3ad

    on_remote_exec "
    bind_vfs
    bind_vfs $NIC2

    require_interfaces VF REP

    # Start OVN
    ifconfig $OVN_BOND $OVN_REMOTE_CONTROLLER_IP
    ovn_set_ovs_config $OVN_REMOTE_SYSTEM_ID $OVN_CENTRAL_IP $OVN_REMOTE_CONTROLLER_IP $TUNNEL_GENEVE
    ovn_start_ovn_controller
    "
}

function pre_test() {
    config
    config_remote
}

function run_test() {
    # Add network topology to OVN
    ovn_create_topology $TOPOLOGY_SINGLE_SWITCH

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

    title "Test ICMP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_icmp_traffic_offload $REP ns0 $IP2

    sleep 2

    title "Test TCP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_remote_tcp_traffic_offload $REP ns0 ns0 $IP2

    sleep 2

    title "Test UDP traffic between $VF($IP1) -> $VF2($IP2) offloaded"
    check_remote_udp_traffic_offload $REP ns0 ns0 $IP2

    sleep 2

    title "Test ICMP6 traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2) offloaded"
    check_icmp6_traffic_offload $REP ns0 $IP_V6_2
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
