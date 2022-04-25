#!/bin/bash

# This is a series of basic tests to check traffic with
# diffrent ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.
# NOTE: tunnel mode is not included in this tests yet.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-offload.sh

require_remote_server

function cleanup() {
    cleanup_crypto
}

function run_test() {
    run_test_ipsec_crypto 1500 ipv6 transport tcp
    run_test_ipsec_crypto 9000 ipv6 transport tcp
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
