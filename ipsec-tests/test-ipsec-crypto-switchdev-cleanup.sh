#!/bin/bash

# Test moving from swithcdev mode to legacy
# mode while ipsec is configured

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function config() {
    ipsec_config_on_both_sides transport 128 ipv4 offload
}

function cleanup() {
    ipsec_cleanup_on_both_sides
    cleanup_crypto
}

function run_test() {
    cleanup
    config
    enable_legacy
}

trap cleanup EXIT
run_test
trap - EXIT
cleanup
test_done
