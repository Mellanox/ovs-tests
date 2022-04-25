#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-offload.sh

require_remote_server

function cleanup(){
    cleanup_crypto
}

#This is a short ipsec test for sanity
function run_test_ipsec_crypto_sanity() {
    local mtu=$1
    local ip_proto=$2
    local ipsec_mode=${3:-"transport"}
    local net_proto=${4:-"tcp"}
    local trusted_vfs=${5:-"no_trusted_vfs"}

    cleanup_crypto $mtu $trusted_vfs
    test_tx_off_rx_off $ipsec_mode 128 $ip_proto $net_proto $trusted_vfs
}

function run_test() {
    run_test_ipsec_crypto_sanity 1500 ipv4 transport tcp
    run_test_ipsec_crypto_sanity 1500 ipv4 transport icmp

}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
