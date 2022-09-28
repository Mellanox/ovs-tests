#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/macsec-common.sh

require_remote_server

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec 1500 on ipv4 ipv6 tcp mac
    run_test_macsec 1500 on ipv6 ipv4 tcp mac
}

trap cleanup EXIT
cleanup
run_test
trap - EXIT
cleanup
test_done
