#!/bin/bash

# This is a series of basic tests to check traffic with
# different ipsec - configurations.In addition it tests if the rules
# which are added are using offload when expected.
# NOTE: in this test local machine is used as Rx.
# NOTE: tunnel mode is not included in this tests yet.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-offload.sh

require_remote_server

function cleanup(){
    cleanup_crypto 1500 trusted_vfs
    ipsec_cleanup_trusted_vfs_on_both_sides
}

function run_test() {
    run_test_ipsec_crypto 1500 ipv4 transport icmp trusted_vfs
    run_test_ipsec_crypto 9000 ipv4 transport icmp trusted_vfs
}

trap cleanup EXIT
ipsec_set_trusted_vfs
ipsec_set_trusted_vfs_on_remote
run_test
trap - EXIT
cleanup
test_done
