#!/bin/bash
#
# Test udp traffic and offload between two sfs on same eswitch.


my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    remove_ns
    ovs_clear_bridges
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    create_sfs 2
    fail_if_err "Failed to create sfs"

    start_clean_openvswitch

    title "SFs Netdev Rep Info"
    SF1=`sf_get_netdev 1`
    SF_REP1=`sf_get_rep 1`
    echo "SF: $SF1, REP: $SF_REP1"

    SF2=`sf_get_netdev 2`
    SF_REP2=`sf_get_rep 2`
    echo "SF: $SF2, REP: $SF_REP2"

    config_ns
    config_ovs
}

function config_ns() {
    config_vf ns0 $SF1 $SF_REP1 $IP1
    config_vf ns1 $SF2 $SF_REP2 $IP2
}

function config_ovs() {
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP1
    ovs-vsctl add-port br-ovs $SF_REP2
}

function remove_ns() {
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
}

function run_traffic() {
    t=15
    echo "run traffic for $((t-2)) seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s -u &
    sleep 2
    ip netns exec ns0 timeout $((t-1)) iperf -u -t $((t-2)) -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP1"
    timeout $((t-5)) tcpdump -qnnei $SF_REP1 -c 10 'udp' &
    pid1=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test traffic offload"
    verify_no_traffic $pid1
}

enable_switchdev $NIC
config
run_traffic
cleanup
trap - EXIT
test_done
