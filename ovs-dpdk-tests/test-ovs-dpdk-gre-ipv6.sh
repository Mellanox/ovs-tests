#!/bin/bash
#
# Test OVS-DPDK with IPv6 gre traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    cleanup_test
    on_remote_exec cleanup_test
}

function config() {
    cleanup

    gre_set_entropy
    config_tunnel ip6gre 1 br-phy br-int $TUNNEL_ID $LOCAL_IP $IPV6_LOCAL_TUNNEL_IP
    config_local_tunnel_ip $IPV6_REMOTE_TUNNEL_IP br-phy 112

    on_remote_exec "config_tunnel ip6gre 1 br-phy br-int $TUNNEL_ID $REMOTE_IP $IPV6_REMOTE_TUNNEL_IP
                    config_local_tunnel_ip $IPV6_LOCAL_TUNNEL_IP br-phy 112"
}

function run() {
    config
    verify_ping
    set_slow_path_percentage 50 "IPV6 uses split STE which requires initalizing extra tables"
    generate_traffic "remote" $LOCAL_IP ns0 true ns0 "local" 15
}

cleanup
run
trap - EXIT
cleanup
test_done
