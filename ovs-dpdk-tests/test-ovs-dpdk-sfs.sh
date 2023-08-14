#!/bin/bash
#
# Test ovs with SFs
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common-sf.sh

enable_switchdev

function cleanup() {
    cleanup_test
    remove_sfs
}

trap cleanup EXIT

function config() {
    cleanup
    create_sfs 2
    ovs_add_bridge
    ovs_add_port "PF"
    ovs_add_port "SF" 1
    ovs_add_port "SF" 2
    config_ns ns0 $SF1 $LOCAL_IP
    config_ns ns1 $SF2 $REMOTE_IP
    ovs-vsctl show
}

function run() {
    config

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup
test_done
