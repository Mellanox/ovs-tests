#!/bin/bash
#
# Test OVS-DPDK with TOS rewrite
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

cleanup_test
config_remote_nic
config_simple_bridge_with_rep 1
start_vdpa_vm
config_ns ns0 $VF $LOCAL_IP

ovs-ofctl add-flow br-phy ip,actions=mod_nw_tos=8,normal

verify_ping
generate_traffic "remote" $LOCAL_IP

check_offload_contains "set.*ipv4.*tos=0x8/0xfc" 2

trap - EXIT
cleanup_test
test_done
