#!/bin/bash
#
# OVS VF LAG test
#
# Bug SW #1788801: [upstream][VF lag] if ovs bridge exist, post ovs restart, the ovs fails to created shared block qdisc on bond
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function config_bonding() {
    ip link add name bond0 type bond || fail "Failed to create bond interface"
    ip link set dev bond0 type bond mode active-backup || fail "Failed to set bond mode"
    ip link set dev $1 down
    ip link set dev $2 down
    ip link set dev $1 master bond0
    ip link set dev $2 master bond0
    ip link set dev bond0 up
    if ! is_bonded ; then
        err "Driver bond failed"
    fi
}

function verify_ingress_block() {
    local i
    for i in bond0 $NIC $NIC2 ; do
        title "Look for ingress_block on $i"
        tc qdisc show dev $i ingress | grep -q ingress_block
        [ $? -ne 0 ] && err "Didn't find ingress_block on $i" || success
    done
}

function test_config_ovs_bond() {
    title "Test config ovs bond"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs

    # bond port is second to reproduce an issue ovs didn't
    # add ingress block so dont put it first.
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs bond0

    # XXX seems we dont get netdev event for slave NIC2
    # so cause an event.
    ip link set dev $NIC2 down
    ip link set dev $NIC2 up

    verify_ingress_block
    start_clean_openvswitch
}

function test_ovs_restart_block_support() {
    title "Test tc block support post ovs restart"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs

    # Bug SW #1788801
    restart_openvswitch

    ovs-vsctl add-port br-ovs bond0

    # XXX seems we dont get netdev event for slave NIC2
    # so cause an event.
    ip link set dev $NIC2 down
    ip link set dev $NIC2 up

    verify_ingress_block
    start_clean_openvswitch
}

function config() {
    echo "- Config"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2
}

function cleanup() {
    ovs-vsctl del-br br-ovs &>/dev/null
    ip link set dev $NIC nomaster
    ip link set dev $NIC2 nomaster
    ip link del bond0 &>/dev/null
}


trap cleanup EXIT
cleanup
config
fail_if_err
test_config_ovs_bond
test_ovs_restart_block_support
test_done
