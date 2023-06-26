#!/bin/bash
#
# Test OVS with vxlan traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

vlan=5
vlan_dev=${REMOTE_NIC}.$vlan

trap 'cleanup_test $vlan_dev' EXIT

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

cleanup_test $vlan_dev


debug "Restarting OVS"
start_clean_openvswitch

config_tunnel vxlan
config_local_tunnel_ip $LOCAL_TUN_IP br-phy
config_remote_tunnel vxlan
config_remote_vlan $vlan $vlan_dev $REMOTE_TUNNEL_IP

ovs-vsctl add-port br-phy pf.$vlan tag=$vlan -- set interface pf.$vlan type=internal
ifconfig pf.$vlan $LOCAL_TUN_IP/24 up
ifconfig br-phy 0

verify_ping $REMOTE_IP

generate_traffic "remote" $LOCAL_IP

test_done
