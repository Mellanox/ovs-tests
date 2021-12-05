#!/bin/bash

#run_traffic ipv4/ipv6 [udp]
function run_traffic() {
    local IP_PROTO="$1"
    local NET_PROTO=${2}
    local IPERF_EXTRA=""
    if [[ "$NET_PROTO" == "tcp" ]]; then
        :
    elif [[ "$NET_PROTO" == "udp" ]]; then
        IPERF_EXTRA="-u"
    else
        err "Wrong arg for function run_traffic"
    fi
    local t=10

    title "Run $NET_PROTO traffic"
    rm -f $TCPDUMP_FILE $IPERF_FILE
    start_iperf_server
    # please notice the no filters on the tcpdump since ipsec encrypt the packets and using crypto offload
    # will require turning TSO/GRO off in some cases in order to capture the expected traffic which will not
    # represent the use case.
    timeout $t tcpdump -qnnei $NIC -c 5 -w $TCPDUMP_FILE &
    local upid=$!
    if [[ "$IP_PROTO" == "ipv4" ]]; then
        (on_remote timeout $((t+2)) iperf3 -c $LIP $IPERF_EXTRA -b 2G > $IPERF_FILE) || err "iperf3 failed"
    else
        (on_remote timeout $((t+2)) iperf3 -c $LIP6 $IPERF_EXTRA -b 2G > $IPERF_FILE) || err "iperf3 failed"
    fi
    fail_if_err

    title "Verify $NET_PROTO traffic on $NIC"
    verify_have_traffic $upid
}

#tx offloaded rx not
function test_tx_off_rx() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded TX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO offload

    sleep 2

    run_traffic $IP_PROTO $NET_PROTO

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
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded RX"

    title "Config ipsec - both sides offloaded"
    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO offload #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO

    sleep 2

    run_traffic $IP_PROTO $NET_PROTO

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
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded TX & RX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO offload #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO offload

    sleep 2

    run_traffic $IP_PROTO $NET_PROTO

    title "verify offload"
    local tx_off=`on_remote ip x s s | grep offload |wc -l`
    local rx_off=`ip x s s | grep offload |wc -l`
    if [[ "$tx_off" != 2 || "$rx_off" != 2 ]]; then
        fail "offload rules are not added as expected!"
    fi
}

function clean_up_crypto() {
    local mtu=${1:-1500}
    ip address flush $NIC
    on_remote ip address flush $REMOTE_NIC
    ipsec_clean_up_on_both_sides
    kill_iperf
    change_mtu_on_both_sides $mtu
    rm -f $IPERF_FILE $TCPDUMP_FILE
}

function run_test_ipsec_crypto() {
    local mtu=$1
    local ip_proto=$2
    local ipsec_mode=${3:-"transport"}
    local net_proto=${4:-"tcp"}
    local len

    for len in 128 256; do
        title "test $ipsec_mode $ip_proto over $net_proto with key length $len MTU $mtu"

        clean_up_crypto $mtu
        test_tx_off_rx $ipsec_mode $len $ip_proto $net_proto
        clean_up_crypto $mtu
        test_tx_rx_off $ipsec_mode $len $ip_proto $net_proto
        clean_up_crypto $mtu
        test_tx_off_rx_off $ipsec_mode $len $ip_proto $net_proto
        clean_up_crypto $mtu
    done
}
