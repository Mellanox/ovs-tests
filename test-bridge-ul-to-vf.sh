#!/bin/bash
#
# Test bridge offloads with ping from VF in namespace to remote setup
# over UL with following configurations:
# 1. Regular traffic with VLAN filtering disabled.
# 2. Both VF and UL are pvid/untagged ports of default VLAN 1.
# 3. Both VF and UL are tagged with VLAN 2.
# 4. VF is tagged with VLAN 3, UL is pvid/untagged with VLAN 3.
# 5. VF is pvid/untagged with VLAN 2, UL is tagged with VLAN 2.
#
# Require external server
#
# Bug SW #2753854: [mlx5, ETH, x86] Traffic lose between 2 VFs with vlans on bridge
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh

min_nic_cx6dx
require_remote_server

br=tst1
LOCAL_IP="7.7.1.7"
LOCAL_MAC="e4:0a:05:08:00:02"
LOCAL_IP_VLAN2="7.7.2.7"
LOCAL_MAC_VLAN2="e4:0a:05:08:00:03"
LOCAL_IP_VLAN3="7.7.3.7"
LOCAL_MAC_VLAN3="e4:0a:05:08:00:04"
REMOTE_IP="7.7.1.1"
REMOTE_MAC="0c:42:a1:58:ac:28"
REMOTE_IP_VLAN2="7.7.2.1"
REMOTE_MAC_VLAN2="0c:42:a1:58:ac:29"
REMOTE_IP_UNTAGGED="7.7.3.1"
namespace1=ns1
time=10
npackets=6

function cleanup() {

    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null
               ip a del $REMOTE_IP/24 dev $REMOTE_NIC &>/dev/null
               ip a del $REMOTE_IP_UNTAGGED/24 dev $REMOTE_NIC &>/dev/null"
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 2
enable_switchdev
require_interfaces REP REP2 NIC
unbind_vfs
bind_vfs
sleep 1

ovs_clear_bridges
remote_disable_sriov
sleep 1

function test_no_vlan() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP $LOCAL_IP $LOCAL_MAC
    ip addr flush dev $NIC
    ip link set dev $NIC up
    ${1:+ip link set $br type bridge vlan_filtering 1}

    on_remote "ip a add dev $REMOTE_NIC $REMOTE_IP/24
               ip link set $REMOTE_NIC up"
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF $br $REMOTE_IP $time $npackets

    on_remote "ip a flush dev $REMOTE_NIC &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

function test_trunk_to_trunk_vlan() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN2 2 $LOCAL_MAC_VLAN2
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 2
    bridge vlan add dev $NIC vid 2

    on_remote "
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2
        ip link set ${REMOTE_NIC}.2 address $REMOTE_MAC_VLAN2
        ip address replace dev ${REMOTE_NIC}.2 $REMOTE_IP_VLAN2/24
        ip link set $REMOTE_NIC up
        ip link set ${REMOTE_NIC}.2 up"
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $REMOTE_IP_VLAN2 $time $npackets

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

function test_trunk_to_access_vlan() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN3 3 $LOCAL_MAC_VLAN3
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 3
    bridge vlan add dev $NIC vid 3 pvid untagged

    on_remote "
        ip link set $REMOTE_NIC address $REMOTE_MAC
        ip a add dev $REMOTE_NIC $REMOTE_IP_UNTAGGED/24
        ip link set $REMOTE_NIC up"
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.3 $br $REMOTE_IP_UNTAGGED $time $npackets

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

function test_access_to_trunk_vlan() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP $LOCAL_IP_VLAN2 $LOCAL_MAC_VLAN2
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 2 pvid untagged
    bridge vlan add dev $NIC vid 2

    on_remote "
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2
        ip link set ${REMOTE_NIC}.2 address $REMOTE_MAC_VLAN2
        ip address replace dev ${REMOTE_NIC}.2 $REMOTE_IP_VLAN2/24
        ip link set $REMOTE_NIC up
        ip link set ${REMOTE_NIC}.2 up"
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF $br $REMOTE_IP_VLAN2 $time $npackets

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

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

cleanup
trap - EXIT
test_done
