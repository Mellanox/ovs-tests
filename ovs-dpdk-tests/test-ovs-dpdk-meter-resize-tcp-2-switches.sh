#!/bin/bash
#
# Test table resize functionality using match on ip src + meter
# this test runs on 2 switches.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev
enable_switchdev $NIC2
bind_vfs
bind_vfs $NIC2

trap cleanup EXIT

function cleanup() {
    ovs_conf_remove ctl-pipe-size
    cleanup_test
}

function config() {
    cleanup
    config_simple_bridge_with_rep 1
    config_simple_bridge_with_rep 1 true br-phy-2 $NIC2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 `get_vf 0 $NIC2` $LOCAL_IP2 "2001:db8:0:f102::1"
    ovs_conf_set ctl-pipe-size 10
    restart_openvswitch
}

function add_openflow_rules() {
    local bridge=${1:-"br-phy"}
    local meter_id=${2:-"1"}
    local pf_port=${3:-`get_port_from_pci $PCI`}
    local ib_pf=${4:-$IB_PF0_PORT0}

    ovs_add_meter $bridge $meter_id pktps 1000000
    exec_dbg "ovs-ofctl -O OpenFlow13 add-flow $bridge \"in_port=$pf_port,ip,tcp,actions=meter=$meter_id,move:NXM_OF_TCP_SRC->NXM_NX_REG12[0..15],$ib_pf\""
    ovs-ofctl -O OpenFlow13 dump-flows $bridge --color
}

function run() {
    config
    config_remote_nic
    config_remote_nic $REMOTE_IP2 "br-phy-2" $NIC2
    add_openflow_rules
    add_openflow_rules "br-phy-2" 2 `get_port_from_pci $PCI2` `get_port_from_pci $PCI2 0`

    verify_ping
    verify_ping $REMOTE_IP2 ns1
    generate_traffic "remote" $LOCAL_IP "none" true "ns0" "local" 5 19
    generate_traffic "remote" $LOCAL_IP2 "none" true "ns1" "local" 5 19
    check_resize_counter
}

run

trap - EXIT
cleanup
test_done
