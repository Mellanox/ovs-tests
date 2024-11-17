#!/bin/bash
#
# Test OVS-DPDK with gre traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup EXIT

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

function cleanup() {
    ovs_conf_remove max-idle
    cleanup_test
}

cleanup_test
config_remote_nic
config_simple_bridge_with_rep 1
config_ns ns0 $VF $LOCAL_IP

ovs-ofctl add-flow br-phy ip,actions=dec_ttl,normal
ovs_conf_set max-idle 300000

verify_ping
generate_traffic "remote" $LOCAL_IP

check_offload_contains "tcp.*ttl=63" 2

trap - EXIT
cleanup
test_done
