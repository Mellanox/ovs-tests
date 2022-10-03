#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/macsec-common.sh

require_remote_server

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec 1500 ipv6 ipv6 udp none
    run_test_macsec 1500 ipv6 ipv6 udp both
}

trap cleanup EXIT
cleanup
run_test
trap - EXIT
cleanup
test_done
