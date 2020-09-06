#!/bin/bash
#
# Test OVS-DPDK with UDP traffic with CT
#
# E2E-CACHE
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=1.1.1.7
IP2=1.1.1.8

config_sriov 2
enable_switchdev
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
    config_ns ns1 $VF2 $IP2
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
    add_openflow_rules

    echo -e "\nTesting UDP traffic"
    t=2
    # traffic
    ip netns exec ns0 iperf -s -u &
    pid1=$!
    sleep 2
    ip netns exec ns1 iperf -c $IP -t $((t+2)) -P 10 -u -l 64 &
    pid2=$!

    # verify pid
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    sleep 5
    # check offloads
    x=$(ovs-appctl dpctl/dump-e2e-stats | grep 'add merged flows messages to HW' | awk '{print $8}')
    echo "Number of offload messages: ";echo $x

    if [ $x -ne 10 ]; then
        err "offloads failed"
    fi

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait

    sleep 10
    # check deletion from DB
    y=$(ovs-appctl dpctl/dump-e2e-stats | grep 'merged flows in e2e cache' | awk '{print $7}')
    echo "Number of DB entries: ";echo $y

    if [ $y -ne 0 ]; then
        err "deletion from DB failed"
    fi

    # check deletion from HW
    z=$(ovs-appctl dpctl/dump-e2e-stats | grep 'delete merged flows messages to HW' | awk '{print $8}')
    echo "Number of delete HW messages: ";echo $z

    if [ $z -ne 10 ]; then
        err "offloads failed"
    fi
}

run
start_clean_openvswitch
test_done
