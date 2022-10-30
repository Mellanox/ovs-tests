#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

eswitch_encap_enable=1

function cleanup() {
    cleanup_crypto
}

#This is a short ipsec test for sanity
function run_test_ipsec_crypto_sanity() {
    local mtu=$1
    local ip_proto=$2
    local ipsec_mode=${3:-"transport"}
    local net_proto=${4:-"tcp"}
    local len=${5:-$IPSEC_KEY_LEN_128}
    local trusted_vfs="no_trusted_vfs"

    cleanup_test $mtu $trusted_vfs
    test_tx_off_rx_off $ipsec_mode $len $ip_proto $net_proto $trusted_vfs
}

function run_test() {
    cleanup
    run_test_ipsec_crypto_sanity 1500 ipv4 transport tcp
    run_test_ipsec_crypto_sanity 1500 ipv4 transport icmp $IPSEC_KEY_LEN_256

}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
