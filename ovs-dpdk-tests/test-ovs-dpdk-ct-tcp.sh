#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT
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
    cleanup_e2e_cache
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable false
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
    ovs-ofctl add-flow br-phy "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo -e "\nOVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    echo -e "\nTesting TCP traffic"
    t=15
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf -s &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) iperf -c $IP -t $t &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # check offloads
    check_dpdk_offloads $IP

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
