#!/bin/bash
#Test macsec extended packet number
#with only one side offloaded to test if
#the driver stays in sync with the kernel stack

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
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto icmp --offload-side none --multi-sa off --xpn on
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto icmp --offload-side local --multi-sa off --xpn on
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
