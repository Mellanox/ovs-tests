#!/bin/bash
#
# Test adding bond0 port
#
# [DOCA Flow] Bug SW #3851918: [OVS DOCA][Bond] Traffic is not offloaded
# [DOCA Flow] Bug SW #3852227: [OVS DOCA][Bond] Traffic with bond in xor mode doesn't pass

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh
. $my_dir/../common-sf.sh

require_remote_server
enable_switchdev

function cleanup() {
    clean_vf_lag
    cleanup_test
    on_remote_exec "config_sriov 2
                    enable_switchdev"
}

trap cleanup EXIT

function clean_vf_lag() {
    # must unbind vfs to create/destroy lag
    unbind_vfs $NIC
    unbind_vfs $NIC2
    clear_bonding
    clear_remote_bonding
}

function config_vf_lag() {
    local mode=${1:-"802.3ad"}

    config_sriov 2 $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2 $mode || fail
    bind_vfs $NIC
    bind_vfs $NIC2
}

function config() {
    config_vf_lag
    remote_disable_sriov
    config_remote_bonding
    on_remote "ip a add $REMOTE_IP/24 dev bond0
               ip a add $REMOTE_IP2/24 dev bond0"
    config_vf ns0 $VF $REP $LOCAL_IP
    VF2=`get_vf 0 $NIC2`
    REP2=`get_rep 0 $NIC2`
    config_vf ns1 $VF2 $REP2 $LOCAL_IP2
}

function check_ping() {
    local ns=$1
    local remote=$2
    title "Check ping to $remote"
    echo "Start tcpdump on $dev"
    timeout 10 tcpdump -nnei $dev -c 4 icmp &
    local pid=$!
    ip netns exec $ns ping -c5 -w 6 $remote || err "ping failed"
    wait $pid
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        err "Not offloaded"
    elif [ "$rc" -eq 124 ]; then
        # tcpdump timeout. offloaded.
        success
    else
        err "tcpdump err $rc"
    fi
}

function run() {
    cleanup
    config
    start_clean_openvswitch
    ovs_add_bridge br-phy
    ovs_add_dpdk_port br-phy bond0
    ovs_add_dpdk_port br-phy $REP
    ovs_add_dpdk_port br-phy $REP2
    ovs-vsctl show
    dev=`get_infiniband_device`
    check_ping ns0 $REMOTE_IP
    check_ping ns1 $REMOTE_IP2
    ovs_clear_bridges
}

run
trap - EXIT
cleanup
test_done
