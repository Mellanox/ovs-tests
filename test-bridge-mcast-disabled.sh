#!/bin/bash
#
# Verify that all other bridge functionality works with multicast disabled.
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
MCAST_IP="224.10.10.10"
MCAST_IP2="224.10.10.11"
MCAST_IP3="224.10.10.12"
namespace1=ns1
namespace2=ns2
namespace3=ns3
time=5

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
    ip netns del $namespace3 &>/dev/null
}
trap cleanup EXIT
cleanup

function create_bridge_with_mcast_flood() {
    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 >/dev/null
    create_bridge_with_interfaces "$@"
    ip link set name $1 type bridge mcast_querier 1 mcast_startup_query_count 10
}

function verify_ping_ns_mcast_no_offload() {
    local ns=$1
    local from_dev=$2
    local dump_dev=$3
    local dst_ip=$4
    local t=$5
    local ndupes=$6
    local npackets=$7
    local filter=${8:-icmp}

    echo "sniff packets on $dump_dev"
    timeout $((t+1)) tcpdump -qnnei $dump_dev -c $npackets ${filter} &
    local tpid=$!
    sleep 0.5

    echo "run ping for $t seconds"
    ip netns exec $ns ping -I $from_dev $dst_ip -c $t -w $t | grep "+$ndupes duplicates" && success || err "Multicast ping failed"
    verify_have_traffic $tpid
}

title "Config local host"
config_sriov 4
enable_switchdev
unbind_vfs
bind_vfs
sleep 1
REP3=`get_rep 2`
VF3=`get_vf 2`
require_interfaces REP REP2 REP3

ovs_clear_bridges
remote_disable_sriov
sleep 1

create_bridge_with_mcast_flood $br $REP $REP2 $REP3
ip link set $br multicast off

ip link set $br type bridge vlan_filtering 1 mcast_vlan_snooping 1
bridge vlan add dev $REP vid 2 pvid untagged
bridge vlan add dev $REP2 vid 2
bridge vlan add dev $REP3 vid 2 pvid untagged
bridge vlan global set dev $br vid 2 mcast_querier 1

config_vf $namespace1 $VF $REP $VF1_IP_VLAN2 $VF1_MAC
config_vf $namespace2 $VF2 $REP2
add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2 $vlan_proto
add_vf_mcast $namespace2 ${VF2}.2 $MCAST_IP
config_vf $namespace3 $VF3 $REP3 $VF3_IP_VLAN2 $VF3_MAC
add_vf_mcast $namespace3 $VF3 $MCAST_IP
sleep 5

bridge mdb add dev $br port enp8s0f0_0 grp $MCAST_IP2 permanent
bridge mdb add dev $br port enp8s0f0_1 grp $MCAST_IP2 permanent
# This command actually disables whole multicast offload
ip link set name $br type bridge mcast_snooping 0

# Try to add some static multicast group just to verify driver handles such case
# correctly with multicast disabled
bridge mdb add dev $br port enp8s0f0_2 grp $MCAST_IP2 permanent

# Cause some IGMP traffic
add_vf_mcast $namespace2 ${VF2}.2 $MCAST_IP3
add_vf_mcast $namespace3 $VF3 $MCAST_IP3

flush_bridge $br
sleep 5
bridge mdb show

verify_ping_ns $namespace1 $VF $br $VF2_IP_VLAN2 $time $time
verify_ping_ns $namespace1 $VF $br $VF3_IP_VLAN2 $time $time
verify_ping_ns_mcast_no_offload $namespace1 $VF $br $MCAST_IP 5 4 5

cleanup
trap - EXIT
test_done
