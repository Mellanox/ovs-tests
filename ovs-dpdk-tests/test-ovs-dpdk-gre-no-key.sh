#!/bin/bash
#
# Test OVS-DPDK with gre no-key traffic
#
# Require external server
#
# Bug SW #3646028: [ovs-dpdk,gre] traffic not offloaded without key in Gre tunnel

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

require_remote_server

gre_set_entropy

config_sriov 2
enable_switchdev
bind_vfs

cleanup_test

function config() {
    config_tunnel gre
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_remote_tunnel gre-no-key
    ovs-vsctl remove interface gre_br-int options key
    start_vdpa_vm
}

function run() {
    config

    verify_ping
    generate_traffic "remote" $LOCAL_IP
}

run
trap cleanup_test EXIT
test_done
