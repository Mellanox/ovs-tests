#!/bin/bash

# This is a series of basic tests to check traffic with
# different ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function cleanup() {
    cleanup_crypto
}

function run_test() {
    run_test_ipsec_offload 1500 ipv4 tunnel icmp
    run_test_ipsec_offload 9000 ipv4 tunnel icmp
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
