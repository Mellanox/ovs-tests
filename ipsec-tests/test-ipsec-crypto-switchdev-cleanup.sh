#!/bin/bash

# Test moving from swithcdev mode to legacy
# mode while ipsec is configured

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

function config() {
    ipsec_config_on_both_sides transport 128 ipv4 offload
}

function clean_up() {
    ipsec_clean_up_on_both_sides
}

function run_test() {
    enable_switchdev
    config
    enable_legacy
}

trap clean_up EXIT
run_test
trap - EXIT
clean_up
test_done
