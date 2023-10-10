#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup EXIT

function cleanup() {
    title "Cleanup"
    ovs_clear_bridges
    reset_tc $NIC $NIC2
    clear_remote_bonding
    set_port_state_up &> /dev/null
    disable_esw_multiport
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    config_devices
    cleanup_test
}

function config_ovs() {
    local pf1=`get_port_from_pci $PCI2`
    local pf1vf0=`get_port_from_pci $PCI2 0`
    local bridge="br-phy"

    config_simple_bridge_with_rep 1 true $bridge $NIC
    exec_dbg ovs-vsctl add-port $bridge $pf1 -- set interface $pf1 type=dpdk options:dpdk-devargs="$PCI,$DPDK_PORT_EXTRA_ARGS,representor=pf1"
    exec_dbg ovs-vsctl add-port $bridge $pf1vf0 -- set Interface $pf1vf0 type=dpdk options:dpdk-devargs="$PCI,representor=pf1vf0,$DPDK_PORT_EXTRA_ARGS"
}

function config_ips() {
    local pf1vf0=`get_vf 0 $NIC2`

    ip a flush dev $VF
    ip a add $LOCAL_IP2/24 dev $VF
    ip a flush dev $pf1vf0
    ip a add $LOCAL_IP/24 dev $pf1vf0
}

function set_interfaces_up() {
    local pf1vf0=`get_vf 0 $NIC2`

    ip link set $NIC up
    ip link set $NIC2 up
    ip link set $VF up
    ip link set $pf1vf0 up
}

function config_remote_ips() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip a flush dev $REMOTE_NIC2
               ip a add $REMOTE_IP2/24 dev $REMOTE_NIC2
               ip l set dev $REMOTE_NIC2 up"
}

function config() {
    title "Config"
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    enable_esw_multiport
    bind_vfs $NIC
    bind_vfs $NIC2
    set_interfaces_up
    config_ovs
    config_ips
    config_remote_ips
}

function run() {
    config

    verify_ping $REMOTE_IP none 56 10
    verify_ping $REMOTE_IP2 none 56 10

    generate_traffic local $REMOTE_IP none true none remote
    generate_traffic local $REMOTE_IP2 none true none remote
}

run
trap - EXIT
cleanup
test_done
