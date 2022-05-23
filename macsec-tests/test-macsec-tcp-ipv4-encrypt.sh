#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/macsec-common.sh

require_remote_server

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec 1500 on ipv4 ipv4 tcp off
    run_test_macsec 1500 on ipv4 ipv4 tcp mac
    title "re-run the test with 9000 mtu\n"
    run_test_macsec 9000 on ipv4 ipv4 tcp off
    run_test_macsec 9000 on ipv4 ipv4 tcp mac
}

trap cleanup EXIT
cleanup
run_test
trap - EXIT
cleanup
test_done
