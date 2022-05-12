#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a VXLAN tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
IP2=1.1.1.15

REMOTE_IP=7.7.7.8
VXLAN_ID=42
DUMMY_IP=8.8.8.8
MIRROR_IP=8.8.8.7

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
    cleanup_mirrors br-int
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP vxlan 2
    add_remote_mirror vxlan br-int 150 $DUMMY_IP $MIRROR_IP
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP2
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function run() {
    config
    config_remote

    t=5
    debug "\nTesting Ping"
    verify_ping $IP ns1

    debug "\nTesting TCP traffic"
    # traffic
    ip netns exec ns0 timeout $((t+2)) iperf3 -s &
    pid1=$!
    sleep 2
    ip netns exec ns1 timeout $((t+2)) iperf3 -c $IP -t $t &
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
    debug "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
