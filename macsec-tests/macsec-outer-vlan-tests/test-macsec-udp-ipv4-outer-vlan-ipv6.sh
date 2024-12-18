#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/../macsec-common.sh

require_remote_server

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto udp --offload-side none --outer-vlan --vlan-ip-proto ipv6
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto udp --offload-side both --outer-vlan --vlan-ip-proto ipv6
}

trap cleanup EXIT
cleanup
run_test
trap - EXIT
cleanup
test_done
