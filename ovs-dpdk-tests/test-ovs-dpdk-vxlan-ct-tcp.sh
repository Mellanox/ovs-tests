#!/bin/bash
#
# Test OVS-DPDK with vxlan TCP traffic with CT
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

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function add_openflow_rules() {
    ovs_add_ct_rules br-int tcp
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP
}

run
trap - EXIT
cleanup_test
test_done
