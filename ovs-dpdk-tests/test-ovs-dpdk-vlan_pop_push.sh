#!/bin/bash
#
# Test OVS with vlan traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

local_vlan=5
remote_vlan=6

remote_vlan_dev=${REMOTE_NIC}.$remote_vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap 'cleanup_test $remote_vlan_dev' EXIT

function config() {
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip link set $VF up

    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 1

    ip netns exec ns0 ip link add $VF.$local_vlan link $VF type vlan id $local_vlan
    ip netns exec ns0 ifconfig $VF.$local_vlan $LOCAL_IP/24

    ovs-ofctl -O OpenFlow13 add-flow br-phy in_port=$NIC,dl_vlan=$remote_vlan,actions=strip_vlan,push_vlan:0x8100,mod_vlan_vid:$local_vlan,$REP
    ovs-ofctl -O OpenFlow13 add-flow br-phy in_port=$REP,dl_vlan=$local_vlan,actions=strip_vlan,push_vlan:0x8100,mod_vlan_vid:$remote_vlan,$NIC

}

cleanup_test $remote_vlan_dev
config
config_remote_vlan $remote_vlan $remote_vlan_dev

# icmp
verify_ping $REMOTE_IP

generate_traffic "remote" $LOCAL_IP

start_clean_openvswitch
test_done
