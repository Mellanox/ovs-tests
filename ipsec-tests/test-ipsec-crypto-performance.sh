#!/bin/bash

#This test compares the performance of ipsec with offload
#to the performance of ipsec without offload, it expects to
#get better results with offload.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function cleanup() {
    cleanup_test
    rm -f /tmp/offload_results.txt /tmp/results.txt
}

function run_test() {
    title "Testing IPsec crypto offload performance"
    #make sure iperf server is down
    kill_iperf
    local mtu
    for mtu in 1500 5250 9000; do
        title "Test with mtu = $mtu"
        change_mtu_on_both_sides $mtu
        run_performance_test transport ipv4
        cleanup
        change_mtu_on_both_sides $mtu
        run_performance_test transport ipv6
        cleanup
    done
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
