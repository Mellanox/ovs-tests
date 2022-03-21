#!/bin/bash
#
# Test OVS DPDK CT ipv6
#
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh


IP="2001:db8:0:f101::1"
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
    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IPV41 $IP
    config_ns ns1 $VF2 $IPV42 $IP2
    # Need to sleep 3 seconds at least for ipv6 address to be added
    sleep 3
}

function run() {
    config
    ovs_add_ct_rules br-phy ip6
    title "Sending icmp"
    verify_ping $IP ns1
    # traffic
    title "Sending traffic"
    generate_traffic "local" $IP ns1
    check_dpdk_offloads $IP2
    check_offloaded_connections 5
}

run
start_clean_openvswitch
test_done
