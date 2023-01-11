#!/bin/bash
#
# Test bridge mcast snooping by verifying that IPv4 IGMP and IPv6 MLD packets
# with destination unicast MAC addresses which are offloaded to FDB are still
# trapped to kernel. Verify both configs with and without VLAN tags.
#
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-br.sh
. $my_dir/common-br-helpers.sh

br=tst1
VF1_IP="7.7.1.7"
VF1_IPV6="2001:0db8:0:f101::1"
VF1_MAC="e4:0a:05:08:00:02"
VF1_IP_VLAN2="7.7.2.7"
VF1_IPV6_VLAN2="2001:0db8:0:f101::3"
VF1_MAC_VLAN2="e4:0a:05:08:00:03"
VF2_IP="7.7.1.1"
VF2_IPV6="2001:0db8:0:f101::2"
VF2_MAC="e4:0a:05:08:00:05"
VF2_IP_VLAN2="7.7.2.1"
VF2_IPV6_VLAN2="2001:0db8:0:f101::4"
VF2_MAC_VLAN2="e4:0a:05:08:00:06"
namespace1=ns1
namespace2=ns2
time=5

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function cleanup() {
    ip link del name $br type bridge 2>/dev/null
    ip netns del $namespace1 &>/dev/null
    ip netns del $namespace2 &>/dev/null
}
trap cleanup EXIT
cleanup

function set_flex_parser_profile() {
    local profile=$1
    fw_config FLEX_PARSER_PROFILE_ENABLE=$profile
}

set_flex_parser_profile 2 || fail "Cannot set flex parser profile"
fw_reset

function run_python_ns() {
    local ns=$1; shift;

    echo "[$ns] python: $@"
    ip netns exec $ns python -c "$@"
}

function test_igmp_no_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    ip link set name $br type bridge ageing_time 3000
    config_vf $namespace1 $VF $REP $VF1_IP $VF1_MAC
    config_vf $namespace2 $VF2 $REP2 $VF2_IP $VF2_MAC
    sleep 1
    flush_bridge $br

    # Warm up to ensure the FDB is in HW
    ip netns exec $namespace1 ping -I $VF $VF2_IP -c 2 -w 2 -q && success || err "Ping failed"

    echo "running udp scapy: [$namespace1] $VF1_MAC/$VF1_IP -> [$namespace2] $VF2_MAC/$VF2_IP"

    timeout 3 tcpdump -qnnei $br -c 1 igmp &
    local tpid=$!
    sleep 1

    # Construct dummy packet with unicast destination MAC address to ensure it
    # is trapped to kernel even with FDB for the address present.
    run_python_ns $namespace1 "from scapy.all import *; from scapy.contrib.igmp import IGMP; h1=Ether(src=\"$VF1_MAC\"); h2=IP(src=\"$VF1_IP\",dst=\"$VF2_IP\"); h3=IGMP(type=0x17,gaddr=\"224.2.3.4\"); p=h1/h2/h3; p[IGMP].igmpize(); p[Ether].dst=\"$VF2_MAC\"; sendp(p, iface=\"$VF\")"
    sleep 1
    verify_have_traffic $tpid

    cleanup_br
}

function test_igmp_trunk_to_trunk_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    ip link set name $br type bridge ageing_time 3000
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IP_VLAN2 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IP_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 2
    bridge vlan add dev $REP2 vid 2
    ip link set $br type bridge vlan_filtering 1
    sleep 1
    flush_bridge $br

    # Warm up to ensure the FDB is in HW
    ip netns exec $namespace1 ping -I $VF.2 $VF2_IP_VLAN2 -c 2 -w 2 -q && success || err "Ping failed"

    echo "running udp scapy: [$namespace1] $VF1_MAC_VLAN2/$VF1_IP_VLAN2 -> [$namespace2] $VF2_MAC_VLAN2/$VF2_IP_VLAN2"

    timeout 3 tcpdump -qnnei $br -c 1 igmp &
    local tpid=$!
    sleep 1

    # Construct dummy packet with unicast destination MAC address to ensure it
    # is trapped to kernel even with FDB for the address present.
    run_python_ns $namespace1 "from scapy.all import *; from scapy.contrib.igmp import IGMP; h1=Ether(src=\"$VF1_MAC_VLAN2\"); h2=IP(src=\"$VF1_IP_VLAN2\",dst=\"$VF2_IP_VLAN2\"); h3=IGMP(type=0x17,gaddr=\"224.2.3.4\"); p=h1/h2/h3; p[IGMP].igmpize(); p[Ether].dst=\"$VF2_MAC_VLAN2\"; sendp(p, iface=\"$VF.2\")"
    sleep 1
    verify_have_traffic $tpid

    cleanup_br
}

function test_mld_no_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    ip link set name $br type bridge ageing_time 3000
    config_vf $namespace1 $VF $REP $VF1_IPV6 $VF1_MAC
    config_vf $namespace2 $VF2 $REP2 $VF2_IPV6 $VF2_MAC
    sleep 3 # IPv6 uses a lot of time to init
    flush_bridge $br

    # Warm up to ensure the FDB is in HW
    ip netns exec $namespace1 ping -I $VF $VF2_IPV6 -c 2 -w 2 -q && success || err "Ping failed"

    echo "running udp scapy: [$namespace1] $VF1_MAC/$VF1_IPV6 -> [$namespace2] $VF2_MAC/$VF2_IPV6"

    timeout 3 tcpdump -qnnei $br -c 1 'ip6 protochain 58 && ip6[48] == 131' &
    local tpid=$!
    sleep 1

    # Construct dummy packet with unicast destination MAC address to ensure it
    # is trapped to kernel even with FDB for the address present.
    run_python_ns $namespace1 "from scapy.all import *; h1=Ether(src=\"$VF1_MAC\",dst=\"$VF2_MAC\"); h2=IPv6(src=\"$VF1_IPV6\",dst=\"ff15::a\",hlim=1); h3=IPv6ExtHdrHopByHop(options=RouterAlert()); h4=ICMPv6MLReport(); p=h1/h2/h3/h4; sendp(p, iface=\"$VF\")"
    sleep 1
    verify_have_traffic $tpid

    cleanup_br
}

function test_mld_trunk_to_trunk_vlan() {
    create_bridge_with_interfaces $br $REP $REP2
    ip link set name $br type bridge ageing_time 3000
    config_vf $namespace1 $VF $REP
    add_vf_vlan $namespace1 $VF $REP $VF1_IPV6_VLAN2 2 $VF1_MAC_VLAN2
    config_vf $namespace2 $VF2 $REP2
    add_vf_vlan $namespace2 $VF2 $REP2 $VF2_IPV6_VLAN2 2 $VF2_MAC_VLAN2

    bridge vlan add dev $REP vid 2
    bridge vlan add dev $REP2 vid 2
    ip link set $br type bridge vlan_filtering 1
    sleep 3 # IPv6 uses a lot of time to init
    flush_bridge $br

    # Warm up to ensure the FDB is in HW
    ip netns exec $namespace1 ping -I $VF.2 $VF2_IPV6_VLAN2 -c 2 -w 2 -q && success || err "Ping failed"

    echo "running udp scapy: [$namespace1] $VF1_MAC_VLAN2/$VF1_IPV6_VLAN2 -> [$namespace2] $VF2_MAC_VLAN2/$VF2_IPV6_VLAN2"

    timeout 3 tcpdump -qnnei $br -c 1 'ip6 protochain 58 && ip6[48] == 131' &
    local tpid=$!
    sleep 1

    # Construct dummy packet with unicast destination MAC address to ensure it
    # is trapped to kernel even with FDB for the address present.
    run_python_ns $namespace1 "from scapy.all import *; h1=Ether(src=\"$VF1_MAC_VLAN2\",dst=\"$VF2_MAC_VLAN2\"); h2=IPv6(src=\"$VF1_IPV6_VLAN2\",dst=\"ff15::a\",hlim=1); h3=IPv6ExtHdrHopByHop(options=RouterAlert()); h4=ICMPv6MLReport(); p=h1/h2/h3/h4; sendp(p, iface=\"$VF.2\")"
    sleep 1
    verify_have_traffic $tpid

    cleanup_br
}

title "Config local host"
config_sriov 2
enable_switchdev
require_interfaces REP REP2 NIC
unbind_vfs
bind_vfs
ovs_clear_bridges
sleep 1

title "test IGMP (no VLAN)"
test_igmp_no_vlan

title "test IGMP (VLAN tagged<->tagged)"
test_igmp_trunk_to_trunk_vlan

title "test MLD (no VLAN)"
test_mld_no_vlan

title "test MLD (VLAN tagged<->tagged)"
test_mld_trunk_to_trunk_vlan

cleanup
trap - EXIT
test_done
