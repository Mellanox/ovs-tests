#!/bin/bash
#
# Test OVS-DOCA openflow meter on second eswitch
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

function test_pre_config() {
    require_interfaces REP REP2 NIC NIC2
    config_devices
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch
}

function config_topology() {
    # first bridge with PF0 is not used, it's just to force first eswitch init
    # in OVS
    config_simple_bridge_with_rep 2

    # second bridge with PF1 will create second eswitch in OVS, where all
    # testing happens
    config_simple_bridge_with_rep 2 true br-phy2 $NIC2
    config_ns ns0 ${VF1/f0/f1} $REMOTE_IP
    config_ns ns1 ${VF2/f0/f1} $LOCAL_IP
}

function run() {
    local max_rate_mbits=400
    local sec=11

    config_topology

    ovs_add_meter br-phy2 1 kbps 100000 10000
    ovs_add_meter br-phy2 2 kbps ${max_rate_mbits}000 ${max_rate_mbits}00

    local pf1_port0=$(get_port_from_pci $PCI2 0)
    local pf1_port1=$(get_port_from_pci $PCI2 1)
    ovs_add_bidir_meter_rules br-phy2 1 2 $pf1_port0 $pf1_port1

    title "Generating traffic"
    generate_traffic_verify_bw $sec $max_rate_mbits

    ovs_del_meter br-phy2 1
    ovs_del_meter br-phy2 2
}

test_pre_config
run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
