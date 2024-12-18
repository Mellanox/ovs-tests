#!/bin/bash
#
# Test ovs-dpdk mac rewrite
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

FAKE_MAC1="e4:11:22:33:44:55"
FAKE_MAC2="e4:11:22:33:44:66"

config_sriov 2
enable_switchdev
bind_vfs

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    title "Setting static neigh rule in ns0 for ip $REMOTE_IP with fake mac $FAKE_MAC1"
    ip netns exec ns0 ip n replace $REMOTE_IP dev $VF lladdr $FAKE_MAC1
    title "Setting static neigh rule in ns1 for ip $LOCAL_IP with fake mac $FAKE_MAC2"
    ip netns exec ns1 ip n replace $LOCAL_IP dev $VF2 lladdr $FAKE_MAC2
}

function add_openflow_rules() {
    local vf1_mac=$(ip netns exec ns0 ip l | grep -A1 "$VF" | grep link | cut -d ' ' -f 6)
    local vf2_mac=$(ip netns exec ns1 ip l | grep -A1 "$VF2" | grep link | cut -d ' ' -f 6)
    local bridge="br-phy"

    debug "Adding mac-rewrite openflow rules"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "table=0,in_port=$IB_PF0_PORT0,ip,dl_dst=$FAKE_MAC1,actions=mod_dl_dst=$vf2_mac,$IB_PF0_PORT1"
    ovs-ofctl add-flow $bridge "table=0,in_port=$IB_PF0_PORT1,ip,dl_dst=$FAKE_MAC2,actions=mod_dl_dst=$vf1_mac,$IB_PF0_PORT0"
    ovs_ofctl_dump_flows
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup_test
test_done
