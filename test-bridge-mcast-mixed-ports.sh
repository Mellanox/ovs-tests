#!/bin/bash
#
# Test bridge offloads with multicast ping from VF in namespace to two other VFs
# (one on same eswitch with VLAN in trunk mode, another one on second eswitch
# with VLAN in access mode) in namespaces and UL in trunk mode.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

br=tst1

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

    on_remote "ip link del link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2 &>/dev/null
               ip a del $REMOTE_IP/24 dev $REMOTE_NIC &>/dev/null
               ip a del $REMOTE_IP_UNTAGGED/24 dev $REMOTE_NIC &>/dev/null"
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
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
sleep 1
REP3=`get_rep 0 $NIC2`
VF3=`get_vf 0 $NIC2`
require_interfaces REP REP2 REP3 NIC NIC2

ovs_clear_bridges
remote_disable_sriov
sleep 1

create_bridge_with_mcast $br $NIC $REP $REP2 $REP3
ip addr flush dev $NIC
ip link set dev $NIC up
on_remote "ip link add link $REMOTE_NIC name ${REMOTE_NIC}.2 type vlan id 2
           ip link set ${REMOTE_NIC}.2 address $REMOTE_MAC_VLAN2
           ip address replace dev ${REMOTE_NIC}.2 $REMOTE_IP_VLAN2/24
           ip link set $REMOTE_NIC up
           ip link set ${REMOTE_NIC}.2 up"

ip link set $br type bridge vlan_filtering 1 mcast_vlan_snooping 1
bridge vlan add dev $REP vid 2 pvid untagged
bridge vlan add dev $REP2 vid 2
bridge vlan add dev $REP3 vid 2 pvid untagged
bridge vlan add dev $NIC vid 2
bridge vlan global set dev $br vid 2 mcast_querier 1

config_vf $namespace1 $VF $REP $VF1_IP_VLAN2 $VF1_MAC
config_vf $namespace2 $VF2 $REP2
add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2 $vlan_proto
add_vf_mcast $namespace2 ${VF2}.2 $MCAST_IP

config_vf $namespace3 $VF3 $REP3 $VF3_IP_VLAN2 $VF3_MAC
add_vf_mcast $namespace3 $VF3 $MCAST_IP

on_remote "sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 >/dev/null
           ip a add dev ${REMOTE_NIC}.2 $MCAST_IP/24 autojoin"

flush_bridge $br
sleep 10
bridge mdb show

verify_ping_ns_mcast $namespace1 $VF $br $MCAST_IP $time $ndups $npackets

cleanup
trap - EXIT
test_done
