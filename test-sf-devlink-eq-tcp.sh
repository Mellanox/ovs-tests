#!/bin/bash
#
# Test SF EQ memory optimizations while changing the eq configuration and running tcp connection.
#
# required minimum kernel 5.17
# Feature Request #2633766: BlueField Memory - ICM consumption per SF/VF improvement
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh
. $my_dir/common-devlink.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip -all netns delete
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    config_sriov 0 $NIC
    enable_switchdev $NIC

    create_sfs 2
    start_clean_openvswitch
}

function config_iter() {
    config_vf ns0 $SF1 $SF_REP1 $IP1
    config_vf ns1 $SF2 $SF_REP2 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP1
    ovs-vsctl add-port br-ovs $SF_REP2
}

function deconfig_iter() {
    ip -netns ns0 link set dev $SF1 netns 1
    ip -netns ns1 link set dev $SF2 netns 1
    ip -all netns delete
    ovs_clear_bridges
}

function run_traffic() {
    local t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP1"
    timeout $((t-4)) tcpdump -qnnei $SF_REP1 -c 10 'tcp' &
    pid=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test traffic offload"
    verify_no_traffic $pid
}

function run() {
    local io_eq_size=256
    local event_eq_size=1024
    local new_io_eq_size
    local new_event_eq_size
    local i

    for i in 1 2 3; do
        new_io_eq_size=$(($io_eq_size * $i))
        new_event_eq_size=$(($event_eq_size * $i))

        title "Configure SFs EQ io_eq_size $new_io_eq_size event_eq_size $new_event_eq_size"

        devlink_dev_set_eq $new_io_eq_size $new_event_eq_size $SF1 $SF2
        config_iter
        run_traffic
        deconfig_iter
    done
}

config
run
cleanup
trap - EXIT
test_done
