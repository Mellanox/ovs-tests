#!/bin/bash
#

my_dir="$(dirname "$0")"
. $my_dir/common-libreswan.sh

require_remote_server

function cleanup() {
    ipsec_clear_setup
    cleanup_crypto
}

function run_test() {
    cleanup
    ipsec_config_setup "crypto" "crypto"

    run_traffic ipv4 icmp

    ipsec_verify_trafficstatus
}

trap cleanup EXIT

run_test

trap - EXIT
cleanup
test_done
