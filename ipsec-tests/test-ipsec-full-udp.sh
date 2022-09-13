#!/bin/bash

# This is a series of basic tests to check traffic with
# different ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.
# NOTE: tunnel mode is not included in this tests yet.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function config() {
    config_full
}

function cleanup() {
    cleanup_full
}

function run_test() {
    run_test_ipsec_offload 1500 ipv4 transport udp no_trusted_vfs full_offload
    run_test_ipsec_offload 9000 ipv4 transport udp no_trusted_vfs full_offload
}

trap cleanup EXIT
config
run_test
trap - EXIT
cleanup
test_done
