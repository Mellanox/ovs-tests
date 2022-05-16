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

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

cleanup_test
set_e2e_cache_enable false

debug "Restarting OVS"
start_clean_openvswitch

config_remote_nic
config_simple_bridge_with_rep 1
start_vdpa_vm
config_ns ns0 $VF $LOCAL_IP

ovs-ofctl add-flow br-phy ip,actions=dec_ttl,normal

verify_ping
generate_traffic "remote"

# check offloads
check_dpdk_offloads $LOCAL_IP
check_offload_contains "ttl=63" 2

start_clean_openvswitch
test_done
