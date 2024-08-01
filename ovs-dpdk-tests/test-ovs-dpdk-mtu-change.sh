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
    local interface=$1
    local mtu=$2

    title "Request MTU $mtu for $interface"
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set interface $interface mtu_request=$mtu
}

function verify_mtu_requesnt() {
    local interface=$1
    local mtu_request=$2

    local mtu=$(ovs-vsctl list interface $interface | grep -w mtu | awk '{ print $3 }')

    title "Check new MTU $mtu >= requested $mtu_request"
    if (( $mtu < $mtu_request )); then
        err "MTU settings didn't change."
    fi
}

function run() {
    local mtu_request=1600
    local pf0=`get_port_from_pci`

    config
    config_remote_nic

    local mtu=$(ovs-vsctl list interface $pf0 | grep -w mtu | awk '{ print $3 }')
    echo "Current MTU $mtu"
    if (( $mtu == $mtu_request )); then
        let mtu_request=mtu_request+100
    fi

    change_mtu_request $pf0 $mtu_request
    # Limitation of ovs-doca, need to restart ovs for the mtu change.
    restart_openvswitch_nocheck
    verify_mtu_requesnt $pf0 $mtu_request

    verify_ping
    check_counters
}

run
trap - EXIT
cleanup_test
test_done
