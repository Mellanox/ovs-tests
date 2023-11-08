#!/bin/bash
#
# Test OVS DPDK CT ipv6
#
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh


LOCAL_IP="2001:db8:0:f101::1"
IP2="2001:db8:0:f101::2"
IPV41="8.8.8.1"
IPV42="8.8.8.2"

trap cleanup_test EXIT

function config() {
    enable_switchdev
    require_interfaces REP REP2 NIC
    unbind_vfs
    bind_vfs
    cleanup_test
    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
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
    ovs-ofctl add-flow $bridge "arp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,icmp,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=0,icmp6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=100,table=0,dl_src=$vf1_mac,dl_dst=$vf2_mac,ip6,ipv6_src=$LOCAL_IP,ipv6_dst=$IP2,nw_proto=6,actions=NORMAL"
    ovs-ofctl add-flow $bridge "priority=100,table=0,dl_src=$vf2_mac,dl_dst=$vf1_mac,ip6,ipv6_dst=$LOCAL_IP,ipv6_src=$IP2,nw_proto=6,actions=NORMAL"
}

function run() {
    config
    add_openflow_rules
    title "Sending ping"
    verify_ping $LOCAL_IP ns1
    # traffic
    title "Sending traffic"
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
