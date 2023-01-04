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
    run_test_macsec --mtu 1500 --ip-proto ipv6 --macsec-ip-proto ipv6 --net-proto tcp --offload-side none
    run_test_macsec --mtu 1500 --ip-proto ipv6 --macsec-ip-proto ipv6 --net-proto tcp --offload-side both
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
