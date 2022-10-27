#!/bin/bash
#
# OVS VF LAG test
#
# Bug SW #1788801: [upstream][VF lag] if ovs bridge exist, post ovs restart, the ovs fails to created shared block qdisc on bond
# Bug SW #1806091: VF-LAG vlan after openvswitch restart ingress traffic not offloaded
# Bug SW #2066643: [Upstream] Traffic and rules fail to pass offload with no offload on one side
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

function wa_for_port2_missing_ingress_block() {
    # XXX seems we dont get netdev event for slave NIC2
    # so cause an event.
    ip link set dev $NIC2 down
    ip link set dev $NIC2 up
}

function test_config_ovs_bond_port_order() {
    title "Test config ovs bond port order"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs

    # bond port is second to reproduce an issue ovs didn't
    # add ingress block so dont put it first.
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs bond0

    wa_for_port2_missing_ingress_block

    verify_ingress_block
    ovs_clear_bridges
}

function test_ovs_restart_block_support() {
    title "Test tc block support post ovs restart"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    # restart ovs after bridge is created but before bond is added

    # Bug SW #1788801: [upstream][VF lag] if ovs bridge exist, post ovs restart,
    # the ovs fails to created shared block qdisc on bond
    restart_openvswitch

    ovs-vsctl add-port br-ovs bond0

    wa_for_port2_missing_ingress_block

    verify_ingress_block
    ovs_clear_bridges
}

# OVS can't reattach qdisc to bond after restart if
# ingress block have rules on it
function test_ovs_restart_block_reattach {
    title "Test block reattach after ovs restart"
    reset_tc bond0 $NIC $NIC2
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs bond0

    local id=$(tc qdisc show dev bond0 | grep ingress_block | awk '{ print $7 }')
    if [[ -z "$id" ]];then
        err "Failed to get bond ingress_block id."
        ovs_clear_bridges
        return
    fi
    title "- Add rule to the ingress_block"
    tc_filter add block $id protocol ip parent ffff: prio 1 flower action drop

    restart_openvswitch

    wa_for_port2_missing_ingress_block

    verify_ingress_block
    ovs_clear_bridges
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

test_config_ovs_bond_port_order
test_ovs_restart_block_support
test_ovs_restart_block_reattach

trap - EXIT
cleanup
test_done
