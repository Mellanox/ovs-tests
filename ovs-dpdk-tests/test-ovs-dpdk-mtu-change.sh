#!/bin/bash
#
# Test OVS-DPDK MTU change.
# This will force reconfigure causing issue.
#
# Bug SW #3511377: [OVS-DOCA] Adding back a PF after having it removed fails on port reconfigure
# Require external server

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 1 true br-phy $NIC
    config_ns ns0 $VF $LOCAL_IP
}

function change_mtu_request() {
    local mtu=$1
    local interface=$2

    debug "Request MTU = $mtu for $interface"
    ovs-vsctl set interface $interface mtu_request=$mtu
}

function run() {
    local mtu_request=1600
    local ib_pf=`get_port_from_pci`

    config
    config_remote_nic
    local mtu=$(ovs-vsctl list interface $ib_pf | grep -w mtu | awk '{ print $3 }')
    if (( $mtu == $mtu_request )); then
        let "mtu_request=mtu_request+100"
    fi
    change_mtu_request 1600 $ib_pf
    restart_openvswitch_nocheck
    mtu=$(ovs-vsctl list interface $ib_pf | grep -w mtu | awk '{ print $3 }')
    if (( $mtu != $mtu_request )); then
        fail "MTU settings didn't change"
    fi

    verify_ping
}

run
check_counters
trap - EXIT
cleanup_test
test_done
