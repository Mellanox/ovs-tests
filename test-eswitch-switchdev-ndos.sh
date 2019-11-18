#!/bin/bash
#
# Verify legacy ndos are block in switchdev mode
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    config_sriov 2
    enable_switchdev_if_no_rep $REP
}

function check_ndo() {
    local ndo=$1
    local value=$2
    ip link set dev $NIC vf 0 $ndo $value 2>/dev/null && err "Expected to fail ndo $ndo" && return
    success
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
}


config
do_test
test_done
