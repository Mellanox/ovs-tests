#!/bin/bash
#
# Test OVS-DPDK with vxlan UDP traffic with CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function config_remote() {
    config_remote_tunnel "vxlan"
}

function run() {
    config
    config_remote
    ovs_add_ct_rules "br-int" "udp"

    verify_ping
    title "Testing UDP traffic"
    t=5
    # traffic
    ip netns exec ns0 timeout -k 1 $((t+2)) iperf -s &
    pid1=$!
    sleep 1
    on_remote timeout -k 1 $((t+2)) iperf -c $LOCAL_IP -t $t -u -l 1000 &
    pid2=$!

    sleep 2
    debug "verify pid"
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    sleep $t
    validate_offload $LOCAL_IP

    killall -9 iperf &>/dev/null
    debug "wait for bgs"
    wait
}

run
trap - EXIT
cleanup_test
test_done
