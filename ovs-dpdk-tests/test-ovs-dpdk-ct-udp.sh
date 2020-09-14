#!/bin/bash
#
# Test OVS-DPDK UDP traffic with CT
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    echo "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $IP
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,udp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,udp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,udp,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo -e "\nOVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    echo -e "\nTesting UDP traffic"
    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf -s -u &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) iperf -c $IP -t $t -u -l 1000 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # check offloads
    x=$(ovs-appctl dpctl/dump-flows -m | grep -v 'ipv6\|icmpv6\|arp\|drop\|ct_state(0x21/0x21)' | grep -- $IP | wc -l)
    echo "Number of filtered rules: ";echo $x
    y=$(ovs-appctl dpctl/dump-flows -m type=offloaded | grep -v 'ipv6\|icmpv6\|arp\|drop\|flow-dump' | wc -l)
    echo "Number of offloaded rules: ";echo $y

    if [ $x -ne $y ]; then
        err "offloads failed"
    fi

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
