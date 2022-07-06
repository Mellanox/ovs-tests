#!/bin/bash
#
# Test OVS-DPDK openflow meters
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

pktgen=$my_dir/../scapy-traffic-tester.py

trap cleanup_test EXIT

NS0_IP=1.1.1.7
NS1_IP=1.1.1.8

#Test pre-req
function test_pre_config() {
    config_sriov 2
    require_interfaces REP NIC
    unbind_vfs
    bind_vfs

    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch
}

function config_topology() {
    config_simple_bridge_with_rep 2

    config_ns ns0 $VF1 $NS0_IP
    config_ns ns1 $VF2 $NS1_IP
}

function run() {
    config_topology

    ovs_add_meter br-phy 1 pktps 1
    ovs_add_simple_meter_rule
    debug "testing meter on PF"
    send_metered_ping
    check_dpdk_offloads $NS0_IP
    ovs_del_meter
    ovs-appctl revalidator/purge

    ovs_add_meter br-phy 1 pktps 50 1
    ovs_add_meter br-phy 2 pktps 50 1
    ovs_add_bidir_meter_rules
    debug "testing meter on REPs"
    ovs_send_scapy_packets $pktgen $VF1 $VF2 $NS0_IP $NS1_IP 1 150 ns0 ns1
    check_dpdk_offloads $NS0_IP
    ovs_check_tcpdump 70
    ovs_del_meter br-phy 1
    ovs_del_meter br-phy 2

}

test_pre_config
run
start_clean_openvswitch
test_done
