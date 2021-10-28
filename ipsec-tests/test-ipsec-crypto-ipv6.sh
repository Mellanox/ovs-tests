#!/bin/bash

# This is a series of basic tests to check traffic with
# diffrent ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.
# NOTE: tunnel mode is not included in this tests yet.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

IPERF_FILE="/tmp/temp1.txt"
TCPDUMP_FILE="/tmp/temp2.txt"

function clean_up() {
    local mtu=${1:-1500}
    ip address flush $NIC
    on_remote ip address flush $REMOTE_NIC
    ipsec_clean_up_on_both_sides
    kill_iperf
    change_mtu_on_both_sides $mtu
    rm -f $IPERF_FILE $TCPDUMP_FILE
}

function run_traffic() {
    local PROTO="$1"

    title "Run traffic"
    local t=10
    start_iperf_server

    timeout $((t+2)) tcpdump -qnnei $NIC -c 15 -w $TCPDUMP_FILE &
    local pid=$!
    if [[ "$PROTO" == "ipv4" ]]; then
        (on_remote timeout $((t+2)) iperf3 -c $LIP -t $t -i 5 > $IPERF_FILE) || err "iperf3 failed"
    else
        (on_remote timeout $((t+2)) iperf3 -c $LIP6 -t $t -i 5 > $IPERF_FILE) || err "iperf3 failed"
    fi
    fail_if_err

    sleep 2

    title "Verify tcp traffic on $NIC"
    verify_have_traffic $pid
    sleep 2

    title "Run UDP traffic"
    kill_iperf
    rm -f $TCPDUMP_FILE $IPERF_FILE
    start_iperf_server

    timeout $t tcpdump -qnnei $NIC -c 5 'udp' -w $TCPDUMP_FILE &
    local upid=$!
    if [[ "$PROTO" == "ipv4" ]]; then
        (on_remote timeout $((t+2)) iperf3 -c $LIP -u -b 2G > $IPERF_FILE) || err "iperf3 failed"
    else
        (on_remote timeout $((t+2)) iperf3 -c $LIP6 -u -b 2G > $IPERF_FILE) || err "iperf3 failed"
    fi
    fail_if_err

    title "Verify udp traffic on $NIC"
    verify_have_traffic $upid
    sleep 2
}

#tx offloaded rx not
function test_tx_off_rx() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local PROTO="$3"
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $PROTO with offloaded TX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $PROTO #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $PROTO offload

    sleep 2

    run_traffic $PROTO

    title "Verify offload"
    local tx_off=`on_remote ip x s s | grep offload |wc -l`
    local rx_off=`ip x s s | grep offload |wc -l`
    if [[ "$tx_off" != 2 || "$rx_off" != 0 ]]; then
        fail "offload rules are not added as expected!"
    fi
}

#rx offloaded tx not
function test_tx_rx_off() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local PROTO="$3"
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $PROTO with offloaded RX"

    title "Config ipsec - both sides offloaded"
    ipsec_config_local $IPSEC_MODE $KEY_LEN $PROTO offload #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $PROTO

    sleep 2

    run_traffic $PROTO

    title "Verify offload"
    local tx_off=`on_remote ip x s s | grep offload |wc -l`
    local rx_off=`ip x s s | grep offload |wc -l`
    if [[ "$tx_off" != 0 || "$rx_off" != 2 ]]; then
        fail "offload rules are not added as expected!"
    fi
}

#tx & rx are offloaded
function test_tx_off_rx_off() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local PROTO="$3"
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $PROTO with offloaded TX & RX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $PROTO offload #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $PROTO offload

    sleep 2

    run_traffic $PROTO

    title "verify offload"
    local tx_off=`on_remote ip x s s | grep offload |wc -l`
    local rx_off=`ip x s s | grep offload |wc -l`
    if [[ "$tx_off" != 2 || "$rx_off" != 2 ]]; then
        fail "offload rules are not added as expected!"
    fi
}

function run_test() {
    local mtu=$1

    title "test transport ipv6 with key length 128 MTU $mtu"

    clean_up $mtu
    test_tx_off_rx transport 128 ipv6
    clean_up $mtu
    test_tx_rx_off transport 128 ipv6
    clean_up $mtu
    test_tx_off_rx_off transport 128 ipv6
    clean_up $mtu

    title "transport ipv6 with key length 256 MTU $mtu"

    clean_up $mtu
    test_tx_off_rx transport 256 ipv6
    clean_up $mtu
    test_tx_rx_off transport 256 ipv6
    clean_up $mtu
    test_tx_off_rx_off transport 256 ipv6
}

trap clean_up EXIT

run_test 1500
run_test 9000

trap - EXIT
clean_up
test_done
