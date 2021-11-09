#!/bin/bash

#This test compares the performance of ipsec with offload
#to the performance of ipsec without offload, it expects to
#get better results with offload.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function config() {
    local proto="$1"
    local should_offload="$2"
    ipsec_clean_up_on_both_sides
    ipsec_config_on_both_sides transport 128 $proto $should_offload
}

function clean_up() {
    ipsec_clean_up_on_both_sides
    kill_iperf
    change_mtu_on_both_sides 1500
    rm -f /tmp/offload_results.txt /tmp/results.txt
}

function run_performance_test() {
    local ip_proto="$1"

    title "Config $ip_proto without offload"
    config $ip_proto

    title "run traffic"
    local t=15
    start_iperf_server_on_remote

    if [[ "$ip_proto" == "ipv4" ]]; then
        (timeout $((t+10)) iperf3 -c $RIP -t $t -i 5 --logfile /tmp/results.txt ) || err "iperf3 failed"
    else
        (timeout $((t+10)) iperf3 -c $RIP6 -t $t -i 5 --logfile /tmp/results.txt ) || err "iperf3 failed"
    fi
    fail_if_err

    title "Config $ip_proto with offload"
    config $ip_proto offload

    kill_iperf
    start_iperf_server_on_remote

    title "run traffic"
    if [[ "$ip_proto" == "ipv4" ]]; then
        (timeout $((t+10)) iperf3 -c $RIP -t $t -i 5 --logfile /tmp/offload_results.txt ) || err "iperf3 failed"
    else
        (timeout $((t+10)) iperf3 -c $RIP6 -t $t -i 5 --logfile /tmp/offload_results.txt ) || err "iperf3 failed"
    fi
    fail_if_err

    title "Check performance"
    no_off_res=`cat /tmp/results.txt | grep "10.*-15.*" | awk '{print $7}'`
    off_res=`cat /tmp/offload_results.txt | grep "10.*-15.*" | awk '{print $7}'`
    #convert to Mbits
    no_off_res=$(bc <<< "$no_off_res * 1000" | sed -e 's/\..*//')
    off_res=$(bc <<< "$off_res * 1000" | sed -e 's/\..*//')

    if [[ $off_res -le $no_off_res ]]; then
        fail "low offload performance"
    fi

}

function run_test() {
    title "Testing IPsec crypto offload performance"
    #make sure iperf server is down
    kill_iperf

    title "Test with mtu = 1500"
    change_mtu_on_both_sides 1500
    run_performance_test ipv4
    clean_up
    change_mtu_on_both_sides 1500
    run_performance_test ipv6
    clean_up

    title "Test with mtu = 5250"
    change_mtu_on_both_sides 5250
    run_performance_test ipv4
    clean_up
    change_mtu_on_both_sides 5250
    run_performance_test ipv6
    clean_up

    title "Test with mtu = 9000"
    change_mtu_on_both_sides 9000
    run_performance_test ipv4
    clean_up
    change_mtu_on_both_sides 9000
    run_performance_test ipv6
}

trap clean_up EXIT
run_test
trap - EXIT
clean_up
test_done
