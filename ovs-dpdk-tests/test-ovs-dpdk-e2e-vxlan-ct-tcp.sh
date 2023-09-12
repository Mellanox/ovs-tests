#!/bin/bash
#
# Test OVS-DPDK with vxlan TCP traffic with CT
#
# E2E-CACHE
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable
    debug "Restarting OVS"
    restart_openvswitch

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function add_openflow_rules() {
    ovs_add_ct_rules br-int tcp
}

function run() {
    config
    config_remote_tunnel vxlan
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP

    check_e2e_stats 10
}

run
trap - EXIT
cleanup_test
test_done
