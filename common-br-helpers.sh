#!/bin/bash

function cleanup_br() {
    ip link del name $br type bridge
    ip -netns $namespace1 link set dev $VF netns 1
    ip -netns $namespace2 link set dev $VF2 netns 1
    ip netns del $namespace1
    ip netns del $namespace2
}

function test_no_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
    config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
    ${1:+ip link set $br type bridge vlan_filtering 1}
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF $br $VF2_IP $time $npackets

    cleanup_br
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

    verify_ping_ns $namespace1 $VF.2 $br $VF2_IP_VLAN2 $time $npackets

    cleanup_br
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

    verify_ping_ns $namespace1 $VF.3 $br $VF2_IP_UNTAGGED $time $npackets

    cleanup_br
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

    verify_ping_ns $namespace1 $VF $br $VF2_IP_VLAN2 $time $npackets

    cleanup_br
}

function test_trunk_to_trunk_qinq() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_qinq $namespace1 $VF $REP $VF1_IP_VLAN2 3 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_qinq $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 3 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 3
    bridge vlan add dev $REP2 vid 3
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.3.2 $br $VF2_IP_VLAN2 $time $npackets 'vlan and vlan and icmp'

    cleanup_br
}

function test_trunk_to_access_qinq() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_qinq $namespace1 $VF $REP $VF1_IP_VLAN2 3 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 3
    bridge vlan add dev $REP2 vid 3 pvid untagged
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.3.2 $br $VF2_IP_VLAN2 $time $npackets 'vlan and vlan and icmp'

    cleanup_br
}

function test_access_to_trunk_qinq() {
    create_bridge_with_interfaces $br $REP $REP2
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN2 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_qinq $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 3 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 3 pvid untagged
    bridge vlan add dev $REP2 vid 3
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $VF2_IP_VLAN2 $time $npackets 'vlan and vlan and icmp'

    cleanup_br
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

    verify_ping_ns $namespace1 $VF.2 $br $VF2_IP_VLAN2 $time $npackets 'vlan and vlan and icmp'

    cleanup_br
}

function test_vf_to_vf_vlan() {
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
}

function test_vf_to_vf_qinq() {
    title "test ping (QinQ tagged<->tagged)"
    test_trunk_to_trunk_qinq

    title "test ping (QinQ tagged<->untagged)"
    test_trunk_to_access_qinq

    title "test ping (QinQ untagged<->tagged)"
    test_access_to_trunk_qinq

    title "test ping (QinQ untagged<->untagged)"
    test_access_to_access_qinq
}

function __test_remote_no_vlan_mcast() {
    local remote_dev=$1

    config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
    add_vf_mcast $namespace1 $VF $MCAST_IP
    config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
    add_vf_mcast $namespace2 $VF2 $MCAST_IP
    config_vf $namespace3 $VF3 $REP3 $VF3_IP $VF3_MAC
    add_vf_mcast $namespace3 $VF3 $MCAST_IP
    flush_bridge $br
    sleep 10
    bridge mdb show

    verify_ping_remote_mcast $remote_dev $br $MCAST_IP $time $ndups $npackets

    ip netns del $namespace1
    ip netns del $namespace2
    ip netns del $namespace3
    sleep 1
}

function test_remote_no_vlan_mcast() {
    create_bridge_with_mcast $br $NIC $REP $REP2 $REP3
    ip addr flush dev $NIC
    ip link set dev $NIC up
    on_remote "ip a add dev $REMOTE_NIC $REMOTE_IP/24
               ip link set $REMOTE_NIC up"

    __test_remote_no_vlan_mcast $REMOTE_NIC

    on_remote "ip a flush dev $REMOTE_NIC &>/dev/null"
    ip link del name $br type bridge
    ip addr flush dev $NIC
    sleep 1
}

function __test_remote_trunk_to_mixed_vlan_mcast() {
    local remote_dev=$1
    local nic=$2
    local vlan_proto=$3

    ip link set $br type bridge vlan_filtering 1 mcast_vlan_snooping 1 vlan_protocol $vlan_proto

    bridge vlan add dev $REP vid 2 pvid untagged
    bridge vlan add dev $REP2 vid 2
    bridge vlan add dev $REP3 vid 2 pvid untagged
    bridge vlan add dev $nic vid 2 pvid untagged
    bridge vlan global set dev $br vid 2 mcast_querier 1

    config_vf $namespace1 $VF $REP $VF1_IP_VLAN2 $VF1_MAC
    add_vf_mcast $namespace1 $VF $MCAST_IP
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2 $vlan_proto
    add_vf_mcast $namespace2 ${VF2}.2 $MCAST_IP
    config_vf $namespace3 $VF3 $REP3 $VF3_IP_VLAN2 $VF3_MAC
    add_vf_mcast $namespace3 $VF3 $MCAST_IP

    flush_bridge $br
    sleep 10
    bridge mdb show

    verify_ping_remote_mcast $remote_dev $br $MCAST_IP $time $ndups $npackets

    ip netns del $namespace1
    ip netns del $namespace2
    ip netns del $namespace3
    sleep 1
}

function test_remote_trunk_to_mixed_vlan_mcast() {
    create_bridge_with_mcast $br $NIC $REP $REP2 $REP3
    ip addr flush dev $NIC
    ip link set dev $NIC up
    on_remote "ip a add dev $REMOTE_NIC $REMOTE_IP_VLAN2/24
               ip link set $REMOTE_NIC up"

    __test_remote_trunk_to_mixed_vlan_mcast $REMOTE_NIC $NIC 802.1Q

    on_remote "ip a flush dev $REMOTE_NIC &>/dev/null"
    ip link del name $br type bridge
    ip addr flush dev $NIC
    sleep 1
}

function test_remote_trunk_to_mixed_qinq_mcast() {
    create_bridge_with_mcast $br $NIC $REP $REP2 $REP3
    ip addr flush dev $NIC
    ip link set dev $NIC up
    on_remote "ip a add dev $REMOTE_NIC $REMOTE_IP_VLAN2/24
               ip link set $REMOTE_NIC up"

    __test_remote_trunk_to_mixed_vlan_mcast $REMOTE_NIC $NIC 802.1ad

    on_remote "ip a flush dev $REMOTE_NIC &>/dev/null"
    ip link del name $br type bridge
    ip addr flush dev $NIC
    sleep 1
}
