#!/bin/bash
#
# Test OVS-DPDK hairpin
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

FAKE_IP=1.1.1.111

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function add_openflow_rules() {
    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp,actions=normal"
    ovs-ofctl add-flow $bridge "in_port=$IB_PF0_PORT0,ip,actions=mod_nw_src=$FAKE_IP,in_port"
    ovs_ofctl_dump_flows
}

function run() {
    config
    add_openflow_rules

    before=`ip netns exec ns0 ifconfig | grep 'RX packets' | awk '{print $3}'`
    ovs_send_scapy_packets $VF $VF2 $LOCAL_IP $REMOTE_IP 1 150 ns0 ns1
    after=`ip netns exec ns0 ifconfig | grep 'RX packets' | awk '{print $3}'`

    # check offloads
    check_dpdk_offloads $LOCAL_IP
    # check sufficient hairpinned packets
    n_pkts=$((after-before))
    debug "received $n_pkts hairpinned packets"
    if [ "$n_pkts" -lt "150" ]; then
        err "expected at least 150 hairpinned packets, received $n_pkts"
    fi
}

run
trap - EXIT
cleanup_test
test_done
