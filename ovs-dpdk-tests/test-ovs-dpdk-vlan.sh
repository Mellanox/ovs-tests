#!/bin/bash
#
# Test OVS with vlan traffic
#
# Require external server
#
my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

vlan=5
vlan_dev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap 'cleanup_test $vlan_dev' EXIT

function config() {
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $LOCAL_IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 1
    ovs-vsctl set port rep0 tag=$vlan
}

cleanup_test $vlan_dev
config
config_remote_vlan $vlan $vlan_dev

# icmp
verify_ping $REMOTE_IP

generate_traffic "remote" $LOCAL_IP

check_dpdk_offloads $LOCAL_IP

start_clean_openvswitch
test_done
