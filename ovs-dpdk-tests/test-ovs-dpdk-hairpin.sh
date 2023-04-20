#!/bin/bash
#
# Test OVS-DPDK hairpin
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

pktgen=$my_dir/../scapy-traffic-tester.py

FAKE_IP=1.1.1.111

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "in_port=rep0,ip,actions=mod_nw_src=$FAKE_IP,in_port"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    before=`ip netns exec ns0 ifconfig | grep 'RX packets' | awk '{print $3}'`
    ovs_send_scapy_packets $pktgen $VF $VF2 $LOCAL_IP $REMOTE_IP 1 150 ns0 ns1
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
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
