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

cleanup_test
remote_ovs_cleanup

function run() {
    config_2_side_tunnel geneve
    ovs_add_ct_rules

    verify_ping

    generate_traffic "remote" $LOCAL_IP ns0

    # check offloads
    check_dpdk_offloads $LOCAL_IP
}

run
cleanup_test
remote_ovs_cleanup
test_done
