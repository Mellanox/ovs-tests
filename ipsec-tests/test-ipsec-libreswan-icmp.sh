#!/bin/bash
#

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec-libreswan.sh

require_remote_server

function cleanup() {
    ipsec_clear_setup
}

function run_test() {
    ipsec_config_setup

    run_traffic ipv4 icmp

    ipsec_verify_trafficstatus
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
