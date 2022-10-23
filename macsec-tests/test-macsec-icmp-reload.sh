#!/bin/bash
#
# Test icmp traffic over macsec and reload modules.
# Bug SW #3237898: call trace and memory leak appears after config macsec and reloading modules
#

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
    run_test_macsec 1500 ipv4 ipv4 icmp both
    title "Reloading modules"
    reload_modules
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
