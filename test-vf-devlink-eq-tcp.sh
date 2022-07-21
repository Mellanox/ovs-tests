#!/bin/bash
#
# Test VF EQ memory optimizations while changing the eq configuration and running tcp connection.
#
# required minimum kernel 5.17
# Feature Request #2633766: BlueField Memory - ICM consumption per SF/VF improvement
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-devlink.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    deconfig_iter
    config_sriov 0 $NIC
}

trap cleanup EXIT

function config() {
    title "Config"
    config_sriov 2 $NIC
    enable_switchdev $NIC
    bind_vfs
    start_clean_openvswitch
}

function config_iter() {
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2
}

function deconfig_iter() {
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

    echo "sniff packets on $REP"
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    local pid=$!

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

        title "Configure VFs EQ io_eq_size $new_io_eq_size event_eq_size $new_event_eq_size"

        devlink_dev_set_eq $new_io_eq_size $new_event_eq_size $VF $VF2
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

