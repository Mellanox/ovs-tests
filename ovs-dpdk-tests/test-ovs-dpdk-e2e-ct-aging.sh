#!/bin/bash
#
# Test OVS-DPDK E2E-CACHE MT aging
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
}

function run() {
    config
    ovs_add_ct_rules "br-phy"

    verify_ping
    generate_traffic "local" $LOCAL_IP ns1
    check_e2e_stats 10 "dpctl/flush-conntrack"
}

run
trap - EXIT
cleanup_test
test_done
