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

function clean_up(){
    clean_up_crypto
}

function run_test() {
    run_test_ipsec_crypto 1500 ipv4 transport tcp
    run_test_ipsec_crypto 9000 ipv4 transport tcp
}

trap clean_up EXIT
run_test
trap - EXIT
clean_up
test_done
