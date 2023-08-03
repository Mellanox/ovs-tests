#!/bin/bash
#
# Test OVS-DPDK UDP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $IP
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy udp
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping
    debug "Testing UDP traffic"
    t=5
    # traffic
    ip netns exec ns0 timeout -k 1 $((t+2)) iperf -s &
    pid1=$!
    sleep 1
    on_remote timeout -k 1 $((t+2)) iperf -c $IP -t $t -u -l 1000 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    sleep $t
    # check offloads
    check_dpdk_offloads $IP

    killall -9 iperf &>/dev/null
    debug "wait for bgs"
    wait
}

run
trap - EXIT
cleanup_test
test_done
