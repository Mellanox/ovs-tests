#!/bin/bash
#
# Test OVS-DPDK VF-VF traffic with remote mirroring
# as a Gre tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP2=1.1.1.15

DUMMY_IP=8.8.8.8
MIRROR_IP=8.8.8.7

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

cleanup_test
cleanup_mirrors br-int

trap cleanup_test EXIT

gre_set_entropy

set_e2e_cache_enable false
debug "Restarting OVS"
start_clean_openvswitch
config_tunnel vxlan 2
start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
add_remote_mirror gre br-int 150 $DUMMY_IP $MIRROR_IP
config_ns ns1 $VF2 $IP2


function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

config_remote

verify_ping $LOCAL_IP ns1

generate_traffic "local" $LOCAL_IP ns1

# check offloads
check_dpdk_offloads $LOCAL_IP

start_clean_openvswitch
test_done
