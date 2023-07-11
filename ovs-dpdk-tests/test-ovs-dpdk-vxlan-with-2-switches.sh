#!/bin/bash
#
# Test OVS with vxlan traffic with 2 bridges and
# 2 vxlan tunnels using different esw managers.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev
enable_switchdev $NIC2
require_interfaces REP NIC NIC2
unbind_vfs
bind_vfs
unbind_vfs $NIC2
bind_vfs $NIC2

trap 'cleanup_test $TUNNEL_DEV2' EXIT

function config() {
    cleanup_test
    config_tunnel "vxlan" 1 br-phy br-int $TUNNEL_ID $LOCAL_IP $REMOTE_TUNNEL_IP $VF $NIC
    config_tunnel "vxlan" 1 br-phy-2 br-int2 $TUNNEL_ID2 $LOCAL_IP2 $REMOTE_TUNNEL_IP2 `get_vf 0 $NIC2` $NIC2
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_local_tunnel_ip $LOCAL_TUN_IP2 br-phy-2
}

function config_remote() {
    config_remote_tunnel vxlan $TUNNEL_DEV $TUNNEL_ID $LOCAL_TUN_IP $REMOTE_TUNNEL_IP $REMOTE_NIC $REMOTE_IP
    config_remote_tunnel vxlan $TUNNEL_DEV2 $TUNNEL_ID2 $LOCAL_TUN_IP2 $REMOTE_TUNNEL_IP2 $REMOTE_NIC2 $REMOTE_IP2 "br-phy-2" $NIC2
}

function run() {
    config
    config_remote

    # icmp
    verify_ping $REMOTE_IP
    verify_ping $REMOTE_IP2

    generate_traffic "remote" $LOCAL_IP
    generate_traffic "remote" $LOCAL_IP2
}

run
trap - EXIT
cleanup_test $TUNNEL_DEV2
test_done
