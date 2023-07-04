#!/bin/bash
#
# Test OVS with vlan vgt traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

VLAN_ID=3458

if [ "${VDPA}" == "1" ]; then
    DEV1=${VDPA_DEV_NAME}
    DEV2=${VDPA_DEV_NAME}
    VLAN_DEV1=${VDPA_DEV_NAME}.${VLAN_ID}
    VLAN_DEV2=${VDPA_DEV_NAME}.${VLAN_ID}
else
    DEV1=${VF}
    DEV2=${VF2}
    VLAN_DEV1=${VF}.${VLAN_ID}
    VLAN_DEV2=${VF2}.${VLAN_ID}
fi

VLAN_IP1="4.4.4.1"
VLAN_IP2="4.4.4.2"

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup EXIT

function cleanup() {
    local dst_execution1="ip netns exec ns0"
    local dst_execution2="ip netns exec ns1"

    if [ "$VDPA}" == "1" ]; then
        dst_execution1="on_vm1"
        dst_execution2="on_vm2"
    fi

    local cmd="$dst_execution1 ip l del $VLAN_DEV1 &>/dev/null"
    eval $cmd
    cmd="$dst_execution2 ip l del $VLAN_DEV2 &>/dev/null"
    eval $cmd

    cleanup_test
}

function config() {
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    start_vdpa_vm $NESTED_VM_NAME1 $NESTED_VM_IP1
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2

    config_vlan_device_ns $DEV1 $VLAN_DEV1 $VLAN_ID $LOCAL_IP $VLAN_IP1 "ns0"
    config_vlan_device_ns $DEV2 $VLAN_DEV2 $VLAN_ID $REMOTE_IP $VLAN_IP2 "ns1"
}

config
ovs_add_ct_rules "br-phy"

verify_ping $VLAN_IP2
generate_traffic "local" $VLAN_IP1 "ns1"

trap - EXIT
cleanup
test_done
