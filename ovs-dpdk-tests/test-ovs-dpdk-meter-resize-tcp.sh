#!/bin/bash
#
# Test table resize functionality using match on ip src + meter
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    ovs_conf_remove ctl-pipe-size
    cleanup_test
}

function config() {
    cleanup
    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $LOCAL_IP
    ovs_conf_set ctl-pipe-size 10
    restart_openvswitch
}

function add_openflow_rules() {
    local bridge="br-phy"
    local meter_id="1"
    local pf_port=`get_port_from_pci $PCI`

    ovs_add_meter $bridge $meter_id pktps 1000000
    exec_dbg "ovs-ofctl -O OpenFlow13 add-flow $bridge \"in_port=$pf_port,ip,tcp,actions=meter=$meter_id,move:NXM_OF_TCP_SRC->NXM_NX_REG12[0..15],$IB_PF0_PORT0\""
    ovs-ofctl -O OpenFlow13 dump-flows $bridge --color
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP "none" true "ns0" "local" 5 19
    check_resize_counter
}

run

trap - EXIT
cleanup
test_done
