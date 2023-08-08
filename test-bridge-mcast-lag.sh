#!/bin/bash
#
# Test bridge offloads with multicast ping from remote setup to three VFs (two
# on the first eswitch, one on the second eswitch) in namespaces via bonded
# links with following configurations:
#
# 1. Simple bridge with bond and VFs attached with VLAN filtering disabled.
#
# 2. Bridge with bond in access mode and VFs mixed (some trunk, some access
# mode) on vid 2 with VLAN filtering enabled.
#
# 3. Bridge with bond in access mode and VFs mixed (some trunk, some access
# mode) on vid 2 with VLAN filtering enabled and VLAN tag set to 802.1ad.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

require_module bonding

br=tst1
bond=bond0


VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
VF1_IP_VLAN2="7.7.2.7"
VF2_IP="7.7.1.8"
VF2_MAC="e4:0a:05:08:00:05"
VF2_IP_VLAN2="7.7.2.8"
VF2_MAC_VLAN2="e4:0a:05:08:00:05"
VF2_IP_UNTAGGED="7.7.3.8"
VF3_IP="7.7.1.9"
VF3_MAC="e4:0a:05:08:00:06"
VF3_IP_VLAN2="7.7.2.9"
REMOTE_IP="7.7.1.1"
REMOTE_MAC="0c:42:a1:58:ac:28"
REMOTE_IP_VLAN2="7.7.2.1"
REMOTE_MAC_VLAN2="0c:42:a1:58:ac:29"
REMOTE_IP_UNTAGGED="7.7.3.1"
MCAST_IP="224.10.10.10"
namespace1=ns1
namespace2=ns2
namespace3=ns3
time=10
ndups=18
npackets=8

require_remote_server
not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    ip netns del $namespace3 &>/dev/null

    clear_remote_bonding
    on_remote "ip a flush dev $REMOTE_NIC
               ip a flush dev $REMOTE_NIC2"

    unbind_vfs
    unbind_vfs $NIC2
    sleep 1
    clear_bonding
    ip a flush dev $NIC
    config_sriov 0 $NIC2
    enable_legacy $NIC2
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 2
enable_switchdev
config_sriov 2 $NIC2
enable_switchdev $NIC2
config_bonding $NIC $NIC2

unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
sleep 1
REP3=`get_rep 0 $NIC2`
VF3=`get_vf 0 $NIC2`
require_interfaces REP REP2 REP3 NIC NIC2

remote_disable_sriov
config_remote_bonding
on_remote "ip address replace dev bond0 $REMOTE_IP/24
           ip l set dev bond0 up"

ovs_clear_bridges
sleep 1

function test_lag_remote_no_vlan_mcast() {
    create_bridge_with_mcast $br $bond $REP $REP2 $REP3

    on_remote "ip address replace dev bond0 $REMOTE_IP/24
               ip l set dev bond0 up"

    __test_remote_no_vlan_mcast bond0

    ip link del name $br type bridge
    on_remote "ip addr flush dev bond0"
    sleep 1
}

function test_lag_remote_trunk_to_mixed_vlan_mcast() {
    create_bridge_with_mcast $br $bond $REP $REP2 $REP3

    on_remote "ip address replace dev bond0 $REMOTE_IP_VLAN2/24
               ip l set dev bond0 up"

    __test_remote_trunk_to_mixed_vlan_mcast bond0 $bond 802.1Q

    ip link del name $br type bridge
    on_remote "ip addr flush dev bond0"
    sleep 1
}

function test_lag_remote_trunk_to_mixed_qinq_mcast() {
    create_bridge_with_mcast $br $bond $REP $REP2 $REP3

    on_remote "ip address replace dev bond0 $REMOTE_IP_VLAN2/24
               ip l set dev bond0 up"

    __test_remote_trunk_to_mixed_vlan_mcast bond0 $bond 802.1ad

    ip link del name $br type bridge
    on_remote "ip addr flush dev bond0"
    sleep 1
}

slave1=$NIC
slave2=$NIC2
remote_active=$REMOTE_NIC

title "test ping (no VLAN)"
change_slaves
test_lag_remote_no_vlan_mcast

title "test ping (VLAN untagged<->mixed)"
change_slaves
test_lag_remote_trunk_to_mixed_vlan_mcast

title "test ping (QinQ untagged<->mixed)"
change_slaves
test_lag_remote_trunk_to_mixed_qinq_mcast

cleanup
trap - EXIT
test_done
