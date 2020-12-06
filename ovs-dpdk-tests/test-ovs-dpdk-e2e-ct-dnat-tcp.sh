#!/bin/bash
#
# Test OVS-DPDK  TCP traffic with CT-CT-NAT
#
# E2E-CACHE
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=1.1.1.7
IP_2=1.1.1.8
DUMMY_IP=1.1.1.20

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_e2e_cache
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable true
    echo "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP_2
    sleep 2
    config_static_arp_ns ns1 ns0 $VF2 $DUMMY_IP
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=normal"
    ovs-ofctl add-flow br-phy "table=0,in_port=rep0,tcp,ct_state=-trk actions=ct(zone=2, table=1)"
    ovs-ofctl add-flow br-phy "table=1,in_port=rep0,tcp,ct_state=+trk+new actions=ct(zone=2, commit, nat(dst=$IP_2:5001)),rep1"
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

    echo -e "\nTesting TCP traffic"
    t=15
    # traffic
    ip netns exec ns1 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 1
    ip netns exec ns0 iperf3 -c $DUMMY_IP -t $t -P 10&
    pid2=$!

    # verify pid
    sleep 3
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    x=$(ovs-appctl dpctl/dump-e2e-stats | grep 'add merged flows messages to HW' | awk '{print $8}')
    echo "Number of offload messages: $x"

    if [ $x -lt 20 ]; then
        err "offloads failed"
    fi

    kill -9 $pid1 &>/dev/null
    killall iperf3 &>/dev/null
    echo "wait for bgs"
    wait

    sleep 15
    # check deletion from DB
    y=$(ovs-appctl dpctl/dump-e2e-stats | grep 'merged flows in e2e cache' | awk '{print $7}')
    echo "Number of DB entries: $y"

    if [ $y -ge 2 ]; then
        err "deletion from DB failed"
    fi

    # check deletion from HW
    z=$(ovs-appctl dpctl/dump-e2e-stats | grep 'delete merged flows messages to HW' | awk '{print $8}')
    echo "Number of delete HW messages: $z"

    if [ $z -lt 20 ]; then
        err "offloads failed"
    fi
}

run
start_clean_openvswitch
test_done
