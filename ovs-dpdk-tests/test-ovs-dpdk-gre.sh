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
debug "Restarting OVS"
start_clean_openvswitch

config_tunnel gre
config_local_tunnel_ip $LOCAL_TUN_IP br-phy
config_remote_tunnel gre
start_vdpa_vm

verify_ping
generate_traffic "remote" $LOCAL_IP

# check offloads
check_dpdk_offloads $LOCAL_IP

start_clean_openvswitch
test_done
