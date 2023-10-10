#!/bin/bash
#
# Test OVS with gre ROCE traffic
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
    cleanup_test

    config_tunnel gre 1 br-phy br-int $TUNNEL_ID $LOCAL_IP $REMOTE_TUNNEL_IP
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy

    on_remote_exec "config_tunnel gre 1 br-phy br-int $TUNNEL_ID $REMOTE_IP $LOCAL_TUN_IP
                    config_local_tunnel_ip $REMOTE_TUNNEL_IP br-phy"

}

function run() {
    config

    verify_ping $REMOTE_IP ns0
    generate_roce_traffic $LOCAL_IP "remote" "local" ns0 ns0
}

cleanup
run
trap - EXIT
cleanup
test_done
