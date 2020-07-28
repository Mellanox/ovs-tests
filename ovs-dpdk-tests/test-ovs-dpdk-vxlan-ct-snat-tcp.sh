#!/bin/bash
#
# Test OVS-DPDK with vxlan TCP traffic with CT
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

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
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    echo "Restarting OVS"
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
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat(dst=4.4.4.11:5001)),rep1"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep1"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep1,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat),rep0"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep1,tcp,ct_state=+trk+est actions=ct(zone=2, nat),rep0"
    echo;echo "OVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules

    echo;echo "Testing TCP traffic"
    t=15
    # traffic
    ip netns exec ns1 timeout $((t+2)) iperf -s &
    pid1=$!
    sleep 1
    ip netns exec ns0 iperf -c $FAKE_IP -t $t &
    pid2=$!

    # verify pid
    sleep 3
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # check offloads
    x=$(ovs-appctl dpctl/dump-flows -m | grep -v 'ipv6\|icmpv6\|arp\|drop\|ct_state(0x21/0x21)' | grep -- $IP'\|tnl_pop' | wc -l)
    echo "Number of filtered rules: ";echo $x
    y=$(ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'ipv6\|icmpv6\|arp\|drop\|flow-dump' | wc -l)
    echo "Number of offloaded rules: ";echo $y

    if [ $x -ne $y ]; then
        err "offloads failed"
    fi

    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}
run
start_clean_openvswitch
test_done
