#!/bin/bash
#
# Test OVS with vxlan traffic with remote mirroring
# as a GRE tunnel and CT
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

MIRROR_IP=8.8.8.8
DUMMY_IP=8.8.8.10

config_sriov 2
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

config_tunnel vxlan
add_remote_mirror gre br-int 150 $DUMMY_IP $MIRROR_IP
config_local_tunnel_ip $LOCAL_TUN_IP br-phy

config_remote_tunnel vxlan
on_remote ip a add $DUMMY_IP/24 dev $REMOTE_NIC

ovs_add_ct_rules

verify_ping

generate_traffic "remote" $LOCAL_IP

start_clean_openvswitch
test_done
