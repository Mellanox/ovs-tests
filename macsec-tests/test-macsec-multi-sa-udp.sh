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
    run_test_macsec 1500 on ipv4 ipv4 udp mac on
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
