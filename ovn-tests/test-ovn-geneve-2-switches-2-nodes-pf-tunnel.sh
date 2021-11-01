#!/bin/bash
#
# Verify no between VFs on different nodes configured with OVN 2 isolated switches
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

require_remote_server

TOPOLOGY=$TOPOLOGY_2_SWITCHES
SWITCH1=$(ovn_get_switch_name_with_vif_port $TOPOLOGY 0)
SWITCH2=$(ovn_get_switch_name_with_vif_port $TOPOLOGY 1)

PORT1=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH1)
MAC1=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH1 $PORT1)
IP1=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH1 $PORT1)
IP_V6_1=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH1 $PORT1)

PORT2=$(ovn_get_switch_vif_port_name $TOPOLOGY $SWITCH2)
MAC2=$(ovn_get_switch_port_mac $TOPOLOGY $SWITCH2 $PORT2)
IP2=$(ovn_get_switch_port_ip $TOPOLOGY $SWITCH2 $PORT2)
IP_V6_2=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SWITCH2 $PORT2)

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

    ifconfig $NIC 0

    ovs_clear_bridges

    # Clean up on remote
    on_remote_exec "
    ovn_remove_ovs_config
    ovn_stop_ovn_controller

    ip -all netns del

    unbind_vfs
    bind_vfs

    ifconfig $NIC 0

    ovs_clear_bridges
    "
}

function config() {
    # Verify NIC
    require_interfaces NIC

    # switchdev mode for NIC
    enable_switchdev
    bind_vfs

    # Verify VFs and REPs
    require_interfaces VF REP

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
    ovn_create_topology $TOPOLOGY

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

    title "Test no traffic between $VF($IP1) -> $VF2($IP2)"
    ip netns exec ns0 ping -w 4 $IP2 && err || success "No Connection"

    title "Test no traffic between $VF($IP_V6_1) -> $VF2($IP_V6_2)"
    ip netns exec ns0 ping -6 -w 4 $IP_V6_2 && err || success "No Connection"
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
