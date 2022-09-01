#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/macsec-common.sh

require_remote_server

function config() {
    config_macsec_env
}

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec 1500 on ipv6 ipv6 icmp off
    run_test_macsec 1500 on ipv6 ipv6 icmp mac
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done