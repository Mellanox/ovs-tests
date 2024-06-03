#!/bin/bash
#
# Test OVS DPDK priority between ipv4 and ipv6 traffic
#
# Feature #3805475: basic pipe
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh


LOCAL_IP="2001:db8:0:f101::1"
IP2="2001:db8:0:f101::2"
IPV41="8.8.8.1"
IPV42="8.8.8.2"

trap cleanup EXIT

function cleanup() {
    ovs_conf_remove max-idle
    cleanup_test
}

function config() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IPV41 $LOCAL_IP
    config_ns ns1 $VF2 $IPV42 $IP2
    # Need to sleep 3 seconds at least for ipv6 address to be added
    sleep 3
}

function add_openflow_rules() {
    local vf1_mac=$(ip netns exec ns0 ip l | grep -A1 "$VF" | grep link | cut -d ' ' -f 6)
    local vf2_mac=$(ip netns exec ns1 ip l | grep -A1 "$VF2" | grep link | cut -d ' ' -f 6)
    local bridge="br-phy"

    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "priority=0,arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,icmp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,icmp6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,ipv6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,ip,actions=NORMAL"
}

function run() {
    config
    add_openflow_rules

    ovs_conf_set max-idle 1000000

    title "Sending ping"
    verify_ping $LOCAL_IP ns1
    verify_ping $IPV41 ns1
    verify_ping $LOCAL_IP ns1
    verify_ping $IPV41 ns1

    local group_dump=`ovs-appctl doca-pipe-group/dump`

    title "doca groups dump"
    echo -e "$group_dump"

    echo -e "$group_dump" | grep "group_id=0" | grep -v "l3_type" | grep "dst_mac" | grep "src_mac" | grep -q "priority=3" || err "ETH/ARP isn't offloaded to prio 2 (LOW)"
    echo -e "$group_dump" | grep "group_id=0" | grep "l3_type\[4,specific]=02000000" | grep -q "priority=2" || err "IPV6 isn't offloaded to prio 1 (MED)"
    echo -e "$group_dump" | grep "group_id=0" | grep "l3_type\[4,specific]=01000000" | grep -q "priority=1" || err "IPV4 isn't offloaded to prio 0 (HIGH)"
}

run
trap - EXIT
cleanup
test_done
