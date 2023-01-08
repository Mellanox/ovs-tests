#!/bin/bash
#
# Verify that bridge removes VLAN that was added on ingress of access port
# before propagation packet on miss path after egress table miss. Test
# implementation pings from access port that adds VLAN 2 to bogus IP address
# that is not configured on any port and verifies that resulting miss-path
# packet captured by tcpdump doesn't have VLAN header.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

min_nic_cx6dx

br=tst1
VF1_IP="7.7.1.7"
VF1_MAC="e4:0a:05:08:00:02"
VF2_IP="7.7.1.1"
VF2_MAC="e4:0a:05:08:00:05"
IP_BOGUS="7.7.1.8"
MAC_BOGUS="e4:0a:05:08:00:06"
namespace1=ns1
namespace2=ns2
time=5

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
}
trap cleanup EXIT
cleanup

title "Config local host"
config_sriov 2
enable_switchdev
require_interfaces REP REP2 NIC
unbind_vfs
bind_vfs
ovs_clear_bridges
sleep 1

create_bridge_with_interfaces $br $REP $REP2
config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
ip netns exec $namespace1 ip neigh add $IP_BOGUS lladdr $MAC_BOGUS dev $VF
config_vf $namespace2 $VF2 $REP2
add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP 2 $VF2_MAC

function verify_ping_miss_no_vlan() {
    local ns=$1
    local from_dev=$2
    local dump_dev=$3
    local dst_ip=$4
    local t=$5

    echo "sniff packets on $dump_dev"
    timeout $t tcpdump -qnnei $dump_dev -c 1 'icmp and vlan' &
    local tpid=$!
    sleep 0.5

    echo "run ping for $time seconds"
    ip netns exec $ns ping -I $from_dev $dst_ip -c $t -w $t -q && fail
    verify_no_traffic $tpid
}

function test_vlan_restore() {
    bridge vlan add dev $REP vid 2 pvid untagged
    bridge vlan add dev $REP2 vid 2
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    verify_ping_miss_no_vlan $namespace1 $VF $REP $IP_BOGUS $time
}

test_vlan_restore

cleanup
trap - EXIT
test_done
