#!/bin/bash

function test_no_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
    config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
    ${1:+ip link set $br type bridge vlan_filtering 1}
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF $br $VF2_IP $time

    ip link del name $br type bridge
    ip netns del $namespace1
    ip netns del $namespace2
    sleep 1
}

function test_trunk_to_trunk_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN2 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 2
    bridge vlan add dev $REP2 vid 2
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $VF2_IP_VLAN2 $time

    ip link del name $br type bridge
    ip netns del $namespace1
    ip netns del $namespace2
    sleep 1
}

function test_trunk_to_access_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN3 3 $VF1_MAC_VLAN3
    config_vf $namespace2 $VF2 $REP2 $VF2_IP_UNTAGGED $VF2_MAC

    bridge vlan add dev $REP vid 3
    bridge vlan add dev $REP2 vid 3 pvid untagged
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.3 $br $VF2_IP_UNTAGGED $time

    ip link del name $br type bridge
    ip netns del $namespace1
    ip netns del $namespace2
    sleep 1
}

function test_access_to_trunk_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP $VF1_IP_VLAN2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 2 pvid untagged
    bridge vlan add dev $REP2 vid 2
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF $br $VF2_IP_VLAN2 $time

    ip link del name $br type bridge
    ip netns del $namespace1
    ip netns del $namespace2
    sleep 1
}

function test_access_to_access_qinq() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN2 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 3 pvid untagged
    bridge vlan add dev $REP2 vid 3 pvid untagged
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $VF2_IP_VLAN2 $time

    ip link del name $br type bridge
    ip netns del $namespace1
    ip netns del $namespace2
    sleep 1
}

function test_vf_to_vf_all() {
    title "test ping (no VLAN)"
    test_no_vlan

    title "test ping (VLAN untagged<->untagged)"
    test_no_vlan filtering

    title "test ping (VLAN tagged<->tagged)"
    test_trunk_to_trunk_vlan

    title "test ping (VLAN tagged<->untagged)"
    test_trunk_to_access_vlan

    title "test ping (VLAN untagged<->tagged)"
    test_access_to_trunk_vlan

    title "test ping (QinQ untagged<->untagged)"
    test_access_to_access_qinq
}
