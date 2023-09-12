#!/bin/bash
#
# Test OVS-DPDK bridge creation and deletion without e2e config first then do the same but with e2e config enabled.
#
# Such test is needed after catching this bug which caused the ovs to get stuck.
# Bug SW #2644904: [ovs-dpdk, e2e-enable] Failed deleting ovs from bridge when we try to cleanup the setup

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    local e2e_setting=$1

    cleanup_test
    set_e2e_cache_enable $e2e_setting
    debug "Restarting OVS"
    restart_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
}

function timeout_ovs-vsctl() {
    local cmd="ovs-vsctl $@"

    bf_wrap "timeout 10 $cmd"
    [ $? -eq 124 ] && err "Timed out command $cmd"
}

function run() {
    title "Test creating tunnel bridges without e2e-enabled"
    config false
    ovs-vsctl show

    debug "deleting bridges (br-int ->> br-phy)"
    timeout_ovs-vsctl del-br br-int
    timeout_ovs-vsctl del-br br-phy

    title "Test creating tunnel bridges with e2e-enabled"
    config true
    ovs-vsctl show

    debug "deleting bridges (br-int ->> br-phy)"
    timeout_ovs-vsctl del-br br-int
    timeout_ovs-vsctl del-br br-phy

    title "Test creating tunnel bridges without e2e-enabled"
    config false
    ovs-vsctl show

    debug "deleting bridges (br-phy ->> br-int)"
    timeout_ovs-vsctl del-br br-phy
    timeout_ovs-vsctl del-br br-int
}

run
trap - EXIT
cleanup_test
test_done
