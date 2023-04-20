#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
# having OVS-DPDK on both sides to cover
# cases which geneve tunnel is not supported by kernel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

trap clean_up EXIT

function clean_up() {
    cleanup_test
    remote_cleanup_test
}

function run() {
    config_2_side_tunnel geneve
    ovs_add_ct_rules

    verify_ping

    generate_traffic "remote" $LOCAL_IP ns0
}

clean_up
run
clean_up
test_done
