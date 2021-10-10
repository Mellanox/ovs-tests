#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with local mirroring
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
IP2=1.1.1.15
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
    ip netns del ns1 &>/dev/null
    cleanup_e2e_cache
    cleanup_mirrors br-phy
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
    add_local_mirror mirror 1 br-phy
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP2
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function run() {
    config
    config_remote

    t=5
    echo -e "\nTesting Ping"
    on_remote timeout $t ping $IP -c 10 -i 0.1 -q
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    echo -e "\nTesting TCP traffic"
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 2
    on_remote timeout $((t+2)) iperf3 -c $IP -t $t &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    sleep $((t-4))
    # check offloads
    check_dpdk_offloads $IP
    kill -9 $pid1 &>/dev/null
    killall iperf3 &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
