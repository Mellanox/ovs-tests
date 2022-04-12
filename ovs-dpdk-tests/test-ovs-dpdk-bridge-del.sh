#!/bin/bash
#
# Test OVS-DPDK bridge creation and deletion
#
# Such test is needed after catching this bug
# Bug SW #2644904: [ovs-dpdk, e2e-enable] Failed deleting ovs from bridge when we try to cleanup the setup

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    cleanup_e2e_cache
    sleep 0.5
}
trap cleanup EXIT

function config() {
    local e2e_setting=$1

    cleanup
    set_e2e_cache_enable $e2e_setting
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
}

function run() {
    debug "creating bridges without e2e-enabled"
    config true
    ovs-vsctl show

    debug "deleting bridges"
    timeout 10 ovs-vsctl del-br br-int
    if [ $? -eq 124 ]; then
        err "Timed out deleting bridge"
    fi
    timeout 10 ovs-vsctl del-br br-phy
    if [ $? -eq 124 ]; then
        err "Timed out deleting bridge"
    fi

    debug "creating bridges with e2e-enabled"
    config true
    ovs-vsctl show

    debug "deleting bridges"
    timeout 10 ovs-vsctl del-br br-int
    if [ $? -eq 124 ]; then
        err "Timed out deleting bridge"
    fi
    timeout 10 ovs-vsctl del-br br-phy
    if [ $? -eq 124 ]; then
        err "Timed out deleting bridge"
    fi
}

run
start_clean_openvswitch
test_done
