#!/bin/bash

# This test configures ipsec with offload
# and verifies traffic when its being
# sent in parallel (from many ips)

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

TCPDUMP_FILE="/tmp/temp.txt"

function config() {
    local L3_PROTO=$1
    ipsec_config_on_both_sides transport 128 $L3_PROTO offload
}

function cleanup() {
    cleanup_test
}

function run_test() {
    local L3_PROTO=$1
    config $L3_PROTO
    sleep 3

    title "Run traffic"
    local t=3
    start_iperf_server

    timeout $((t+2)) tcpdump -qnnei $NIC -c 20 -w $TCPDUMP_FILE &
    local pid=$!

    if [[ "$L3_PROTO" == "ipv4" ]]; then
        (on_remote timeout $((t+2)) iperf3 -c $LIP --parallel 5 -t $t) || err "iperf3 failed"
    else
        (on_remote timeout $((t+2)) iperf3 -c $LIP6 --parallel 5 -t $t) || err "iperf3 failed"
    fi
    fail_if_err
    sleep 3

    title "Verify traffic on $NIC"
    verify_have_traffic $pid
    sleep 3
}

trap cleanup EXIT
run_test ipv4
cleanup
run_test ipv6
cleanup
change_mtu_on_both_sides 9000
run_test ipv4
cleanup
change_mtu_on_both_sides 9000
run_test ipv6
trap - EXIT
cleanup
test_done
