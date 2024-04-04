#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

min_nic_cx6dx
require_remote_server

trap cleanup EXIT

function cleanup_mpesw() {
    ovs_clear_bridges
    reset_tc $NIC $NIC2 $REP
    clear_remote_bonding
    ip netns del ns0 &> /dev/null
    set_port_state_up &> /dev/null
    disable_esw_multiport
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    reload_modules
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    bind_vfs
    ip link set $NIC up
    ip link set $NIC2 up
}

function cleanup() {
    title "Cleaning up local"
    cleanup_mpesw
    cleanup_test
    on_remote_exec "config_sriov 2
                    config_sriov 2 $NIC2
                    enable_switchdev
                    enable_switchdev $NIC2
                    bind_vfs
                    bind_vfs $NIC2
                    ip link set $NIC up
                    ip link set $NIC2 up"
}

function add_openflow_rules() {
    local pci=`get_pf_pci`
    local port=`get_port_from_pci $pci`
    local pci2=`get_pf_pci2`
    local port2=`get_port_from_pci $pci2`

    local bridge="br-phy"
    ovs-ofctl del-flows $bridge
    ovs-ofctl add-flow $bridge "arp, actions=normal"
    ovs-ofctl add-flow $bridge "in_port=$port,ip actions=$port2"
    ovs-ofctl add-flow $bridge "in_port=$port2,ip actions=$port"

    debug "OVS flow rules:"
    ovs-ofctl dump-flows $bridge --color
}

function set_interfaces_up() {
    ip link set $NIC up
    ip link set $NIC2 up
}

function config_ovs() {
    local pci=`get_pf_pci`
    local pci2=`get_pf_pci2`
    local port2=`get_port_from_pci $pci2`

    title "Config OVS"
    start_clean_openvswitch
    config_simple_bridge_with_rep 0
    ovs-vsctl add-port br-phy $port2 -- set interface $port2 type=dpdk options:dpdk-devargs="$pci,$DPDK_PORT_EXTRA_ARGS,representor=pf1"
    ovs-vsctl show
}

function config_remote() {
    title "Config remote"
    remote_disable_sriov
    on_remote_exec "enable_legacy $NIC
                    enable_legacy $NIC2
                    config_ns ns0 $NIC $LOCAL_IP
                    config_ns ns1 $NIC2 $REMOTE_IP"
}

function config_mpesw() {
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
}

function config() {
    config_mpesw
    config_ovs
    add_openflow_rules
    config_remote
}

function run_test() {
    config
    on_remote_exec "verify_ping $REMOTE_IP
                    generate_traffic "local" $LOCAL_IP ns1"
    check_dpdk_offloads $LOCAL_IP
}

run_test
trap - EXIT
cleanup
test_done
