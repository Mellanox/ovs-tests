#!/bin/bash
#
# Test OVS DPDK DOCA split bug
#
# Bug was not matching ipv6_dst. Test tries to add a rule that will be
# split and then checks if ipv6_dst was matched by testing two different
# actions (fwd, drop) based on ipv6_dst.
#
# Bug SW #3857823: [OVS-DOCA] Suffix split rule loses match ipv6_dst
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function config() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    cleanup_test
    config_simple_bridge_with_rep 2

    config_ns ns0 $VF $LOCAL_IP $LOCAL_IPV6
    config_ns ns1 $VF2 $REMOTE_IP $REMOTE_IPV6

    ip netns exec ns1 ip -6 address add $REMOTE_IPV62/64 dev $VF2

    # Need to sleep 3 seconds at least for ipv6 address to be added
    sleep 3
}

function add_openflow_rules() {
    local vf1_mac=$(ip netns exec ns0 ip l | grep -A1 "$VF" | grep link | cut -d ' ' -f 6)
    local vf2_mac=$(ip netns exec ns1 ip l | grep -A1 "$VF2" | grep link | cut -d ' ' -f 6)
    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "priority=2,icmp6,ipv6_src=$LOCAL_IPV6,ipv6_dst=$REMOTE_IPV62,dl_src=$vf1_mac,dl_dst=$vf2_mac,actions=drop"
    ovs-ofctl add-flow $bridge "priority=2,icmp6,ipv6_src=$LOCAL_IPV6,ipv6_dst=$REMOTE_IPV6,dl_src=$vf1_mac,dl_dst=$vf2_mac,actions=normal"
    ovs-ofctl add-flow $bridge "priority=1,arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=1,ip6,actions=NORMAL"
}

function run() {
    config
    add_openflow_rules

    # First run drop traffic so if bug occurs where it doesn't
    # match destination IP and next ping will fail
    ip netns exec ns0 timeout 2 ping -6 -c 1 -w 2 $REMOTE_IPV62

    verify_ping $REMOTE_IPV6 ns0

    check_offload_contains "src=$LOCAL_IPV6,dst=$REMOTE_IPV6.*actions:[^d][^r]" 1
    check_offload_contains "src=$LOCAL_IPV6,dst=$REMOTE_IPV62.*actions:drop" 1
}

run
trap - EXIT
cleanup_test
test_done
