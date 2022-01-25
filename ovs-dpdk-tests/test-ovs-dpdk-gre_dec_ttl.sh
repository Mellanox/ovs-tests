#!/bin/bash
#
# Test OVS-DPDK with gre traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

require_remote_server

gre_set_entropy

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

cleanup_test
set_e2e_cache_enable false
echo "Restarting OVS"
start_clean_openvswitch

config_tunnel gre
config_local_tunnel_ip $LOCAL_TUN_IP br-phy
config_remote_tunnel gre
ovs-ofctl add-flow br-int ip,actions=dec_ttl,normal
verify_ping
generate_traffic "remote"

# check offloads
check_dpdk_offloads $LOCAL_IP
check_offload_contains "ttl=63" 2

start_clean_openvswitch
test_done
