#!/bin/bash
#
# OVS VF LAG test
#
# Bug SW #2043842: [Upstream] ingress_block could be missing after adding bond to ovs or restarting ovs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

function verify_ingress_block() {
    local i
    for i in bond0 $NIC $NIC2 ; do
        title "- Look for ingress_block on $i"
        tc qdisc show dev $i ingress | grep -q ingress_block
        [ $? -eq 0 ] && success || err "Didn't find ingress_block on $i"
    done
}

function test_config_ovs_bond_simple() {
    title "Test config ovs bond simple"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs

    # If we start with port down it also doesn't reproduce the issue
    # if ports are up, OVS doesn't add the ingress block.
    # dont uncomment as thats the purpose of the case.
#    ifconfig $NIC down
#    ifconfig $NIC2 down

    ovs-vsctl add-port br-ovs bond0
    ovs-vsctl add-port br-ovs $REP

    verify_ingress_block
    del_all_bridges
}

function test_config_ovs_bond_after_cleanup() {
    title "Test config ovs bond after ovs restart"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs bond0

    stop_openvswitch
    reset_tc bond0 $NIC $NIC2
    restart_openvswitch

    verify_ingress_block
    del_all_bridges
}

function config() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    config_bonding $NIC $NIC2
}

function cleanup() {
    ovs-vsctl del-br br-ovs &>/dev/null
    clear_bonding
}


trap cleanup EXIT
cleanup
config
fail_if_err
test_config_ovs_bond_simple
test_config_ovs_bond_after_cleanup
test_done
