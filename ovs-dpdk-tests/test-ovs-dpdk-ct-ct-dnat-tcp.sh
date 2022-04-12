#!/bin/bash
#
# Test OVS-DPDK with TCP traffic and
# CT-CT-DNAT rules
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=4.4.4.10
IP_2=4.4.4.11
FAKE_IP=4.4.4.111

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_e2e_cache
    cleanup_ct_ct_nat_offload
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable false
    enable_ct_ct_nat_offload
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP_2
    sleep 2
    config_static_arp_ns ns1 ns0 $VF2 $FAKE_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep0,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat(dst=4.4.4.11:5201)),rep1"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep1"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep1,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat),rep0"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep0"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    debug "Testing TCP traffic"
    t=15
    # traffic
    ip netns exec ns1 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 1
    ip netns exec ns0 iperf3 -c $FAKE_IP -t $t -P 5 &
    pid2=$!

    # verify pid
    sleep 3
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    sleep $((t-4))
    # check offloads
    check_dpdk_offloads $IP
    check_offloaded_connections 5
    killall iperf3 &>/dev/null
    debug "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
