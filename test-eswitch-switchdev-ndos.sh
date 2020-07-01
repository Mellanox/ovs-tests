#!/bin/bash
#
# Verify legacy ndos are block in switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 2
    enable_switchdev
}

function check_ndo() {
    local ndo=$1
    local value=$2
    ip link set dev $NIC vf 0 $ndo $value 2>/dev/null && err "Expected to fail ndo $ndo" && return
    success
}

function set_ndo() {
    local ndo=$1
    local value=$2
    ip link set dev $NIC vf 0 $ndo $value 2>/dev/null || err "Failed to set ndo $ndo to $value"
}

function check_bridge_link_set() {
    bridge link set dev $NIC hwmode vepa 2>/dev/null && err "Expected to fail ndo bridge" && return
    success
}

function check_bridge_link_get() {
    # this function always return 0 so check output
    local out
    out=`bridge link show dev $NIC 2>/dev/null`
    if [ -n "$out" ]; then
        err "Expected to fail ndo bridge" && return
    fi
    success
}

function check_create_vlan() {
    # check can create vlan on uplink rep
    local vlan_dev=${NIC}.5
    ip link add link $NIC name $vlan_dev type vlan id 5
    local rc=$?
    ip link del $vlan_dev &>/dev/null
    if [ $rc != 0 ]; then
        err "Failed to create vlan interface"
    else
        success
    fi
}

function do_test() {
    title "Verify legacy ndos are blocked in switchdev mode"

    title "- test bridge link set"
    check_bridge_link_set

    title "- test bridge link get"
    check_bridge_link_get

    title "- test spoofchk"
    check_ndo spoofchk on

    title "- test trust"
    check_ndo trust on

    title "- test state"
    check_ndo state auto

    title "- test rate"
    set_ndo rate 0

    title "- test vf vlan"
    check_ndo vlan 1
    set_ndo vlan 0

    title "- test vlan"
    check_create_vlan
}


config
do_test
test_done
