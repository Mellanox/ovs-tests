#!/bin/bash
#
# Test bridge offloads with ping from VF in namespace to remote setup
# over UL with following configurations:
# 6. VF is tagged with VLAN 2 in namespace and pvid/untagged with 802.1ad VLAN 3
# (QinQ) on bridge, UL is pvid/untagged with VLAN 3.
# 7. VF is tagged with VLAN 2 in namespace and pvid/untagged with 802.1ad VLAN 3
# (QinQ) on bridge, UL is pvid/untagged with 802.1ad VLAN 3.
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
time=5

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

function test_trunk_to_trunk_qinq() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP
    add_vf_qinq $namespace1 $VF $REP $LOCAL_IP_VLAN2 3 2 $LOCAL_MAC_VLAN2
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 3
    bridge vlan add dev $NIC vid 3

    on_remote "
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.3 type vlan id 3 protocol 802.1ad
        ip link add link ${REMOTE_NIC}.3 name ${REMOTE_NIC}.3.2 type vlan id 2
        ip link set ${REMOTE_NIC}.3.2 address $REMOTE_MAC_VLAN2
        ip address replace dev ${REMOTE_NIC}.3.2 $REMOTE_IP_VLAN2/24
        ip link set $REMOTE_NIC up
        ip link set ${REMOTE_NIC}.3 up
        ip link set ${REMOTE_NIC}.3.2 up"
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.3.2 $br $REMOTE_IP_VLAN2 $time $time 'vlan and vlan and icmp'

    on_remote "
              ip link del link $REMOTE_NIC name ${REMOTE_NIC}.3.2 type vlan id 2 &>/dev/null
              ip link del link $REMOTE_NIC name ${REMOTE_NIC}.3 type vlan id 3 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

function test_access_to_trunk_qinq() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN2 2 $LOCAL_MAC_VLAN2
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 3 pvid untagged
    bridge vlan add dev $NIC vid 3

    on_remote "
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.3 type vlan id 3 protocol 802.1ad
        ip link add link ${REMOTE_NIC}.3 name ${REMOTE_NIC}.3.2 type vlan id 2
        ip link set ${REMOTE_NIC}.3.2 address $REMOTE_MAC_VLAN2
        ip address replace dev ${REMOTE_NIC}.3.2 $REMOTE_IP_VLAN2/24
        ip link set $REMOTE_NIC up
        ip link set ${REMOTE_NIC}.3 up
        ip link set ${REMOTE_NIC}.3.2 up"
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $REMOTE_IP_VLAN2 $time $time 'vlan and vlan and icmp'

    on_remote "
              ip link del link $REMOTE_NIC name ${REMOTE_NIC}.3.2 type vlan id 2 &>/dev/null
              ip link del link $REMOTE_NIC name ${REMOTE_NIC}.3 type vlan id 3 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

function test_access_to_access_qinq() {
    create_bridge_with_interfaces $br $NIC $REP
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $LOCAL_IP_VLAN2 2 $LOCAL_MAC_VLAN2
    ip addr flush dev $NIC
    ip link set dev $NIC up

    bridge vlan add dev $REP vid 3 pvid untagged
    bridge vlan add dev $NIC vid 3 pvid untagged

    on_remote "
        ip link add link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2
        ip link set ${REMOTE_NIC}.2 address $REMOTE_MAC_VLAN2
        ip address replace dev ${REMOTE_NIC}.2 $REMOTE_IP_VLAN2/24
        ip link set $REMOTE_NIC up
        ip link set ${REMOTE_NIC}.2 up"
    ip link set $br type bridge vlan_filtering 1 vlan_protocol 802.1ad
    sleep 1
    flush_bridge $br

    verify_ping_ns $namespace1 $VF.2 $br $REMOTE_IP_VLAN2 $time $time 'vlan and vlan and icmp'

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null"
    ip link del name $br type bridge
    ip netns del $namespace1
    ip addr flush dev $NIC
    sleep 1
}

title "test ping (QinQ tagged<->tagged)"
test_trunk_to_trunk_qinq

title "test ping (QinQ untagged<->tagged)"
test_access_to_trunk_qinq

title "test ping (QinQ untagged<->untagged)"
test_access_to_access_qinq

cleanup
trap - EXIT
test_done
