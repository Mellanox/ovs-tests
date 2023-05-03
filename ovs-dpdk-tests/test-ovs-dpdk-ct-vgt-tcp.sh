#!/bin/bash
#
# Test OVS with vlan vgt traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

VLAN_ID=3458
VLAN_DEV1=${VF}.${VLAN_ID}
VLAN_DEV2=${VF2}.${VLAN_ID}
VLAN_IP1="4.4.4.1"
VLAN_IP2="4.4.4.2"

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup EXIT

function cleanup() {
    ip netns exec ns0 ip l del $VLAN_DEV1 &>/dev/null
    ip netns exec ns1 ip l del $VLAN_DEV2 &>/dev/null
    cleanup_test
}

function config() {
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2

    config_vlan_device_ns $VF $VLAN_DEV1 $VLAN_ID $LOCAL_IP $VLAN_IP1 "ns0"
    config_vlan_device_ns $VF2 $VLAN_DEV2 $VLAN_ID $REMOTE_IP $VLAN_IP2 "ns1"
}

config
ovs_add_ct_rules "br-phy"

verify_ping $VLAN_IP2
generate_traffic "local" $VLAN_IP1 "ns1"

ovs_clear_bridges
test_done
