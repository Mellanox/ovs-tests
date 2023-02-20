#!/bin/bash
#Test macsec basic functionality while
#only one side is offloaded to test if
#the driver stays in sync with the kernel stack

my_dir="$(dirname "$0")"
. $my_dir/../macsec-common.sh

require_remote_server

function config() {
    config_macsec_env
}

function cleanup() {
    macsec_cleanup
}

function run_test() {
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto icmp --offload-side local --inner-vlan --vlan-ip-proto ipv4
    run_test_macsec --mtu 1500 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto tcp --offload-side local --inner-vlan --vlan-ip-proto ipv4

    echo
    title "re-run the test with 9000 mtu"

    run_test_macsec --mtu 9000 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto icmp --offload-side local --inner-vlan --vlan-ip-proto ipv4
    run_test_macsec --mtu 9000 --ip-proto ipv4 --macsec-ip-proto ipv4 --net-proto tcp --offload-side local --inner-vlan --vlan-ip-proto ipv4
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
