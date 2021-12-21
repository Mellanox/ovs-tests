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

function run_test() {
    ovn_config_interface_namespace $VF $REP ns0 $PORT1 $MAC1 $IP1 $IP_V6_1
    on_remote_exec "ovn_config_interface_namespace $VF $REP ns0 $PORT2 $MAC2 $IP2 $IP_V6_2"

    ovs-vsctl show
    ovn-sbctl show

    title "Test no traffic between $VF($IP1) -> $VF($IP2)"
    ip netns exec ns0 ping -w 4 $IP2 && err || success "No Connection"

    title "Test no traffic between $VF($IP_V6_1) -> $VF($IP_V6_2)"
    ip netns exec ns0 ping -6 -w 4 $IP_V6_2 && err || success "No Connection"
}

HAS_REMOTE=1

ovn_execute_test
