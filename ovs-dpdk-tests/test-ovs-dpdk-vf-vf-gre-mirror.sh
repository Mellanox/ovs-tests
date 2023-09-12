#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a Gre tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

DUMMY_IP=8.8.8.8
MIRROR_IP=8.8.8.7

config_sriov 2
enable_switchdev
bind_vfs

cleanup_test
cleanup_mirrors br-int

trap cleanup_test EXIT

gre_set_entropy

debug "Restarting OVS"
start_clean_openvswitch
config_tunnel vxlan 2
start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
add_remote_mirror gre br-int 150 $DUMMY_IP $MIRROR_IP
config_ns ns1 $VF2 $REMOTE_IP

config_remote_nic $DUMMY_IP

verify_ping $LOCAL_IP ns1

generate_traffic "local" $LOCAL_IP ns1

start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
