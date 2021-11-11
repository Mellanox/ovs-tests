#!/bin/bash

# This is a series of basic tests to check traffic with
# diffrent ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.
# NOTE: tunnel mode is not included in this tests yet.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-crypto.sh

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

function run_test() {
    local mtu=$1

    title "test transport ipv4 with key length 128 MTU $mtu"

    clean_up $mtu
    test_tx_off_rx transport 128 ipv4 tcp
    clean_up $mtu
    test_tx_rx_off transport 128 ipv4 tcp
    clean_up $mtu
    test_tx_off_rx_off transport 128 ipv4 tcp
    clean_up $mtu

    title "transport ipv4 with key length 256 MTU $mtu"

    clean_up $mtu
    test_tx_off_rx transport 256 ipv4 tcp
    clean_up $mtu
    test_tx_rx_off transport 256 ipv4 tcp
    clean_up $mtu
    test_tx_off_rx_off transport 256 ipv4 tcp
}

trap clean_up EXIT

run_test 1500
run_test 9000

trap - EXIT
clean_up
test_done
