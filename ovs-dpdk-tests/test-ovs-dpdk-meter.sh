#!/bin/bash
#
# Test OVS-DPDK openflow meters
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

NS0_IP=1.1.1.7
NS1_IP=1.1.1.8

#Test pre-req
function test_pre_config() {
    config_sriov 2
    enable_switchdev
    bind_vfs

    cleanup_test
}

function config_topology() {
    config_simple_bridge_with_rep 2

    config_ns ns0 $VF1 $NS0_IP
    config_ns ns1 $VF2 $NS1_IP
}

function run() {
    config_topology

    ovs_add_meter br-phy 1 pktps 3
    ovs_add_simple_meter_rule
    title "Testing meter on PF"
    send_metered_ping
    check_dpdk_offloads $NS0_IP
    ovs_del_meter
    ovs-appctl revalidator/purge

    local rate=50
    ovs_add_meter br-phy 1 pktps $rate 1
    ovs_add_meter br-phy 2 pktps $rate 1
    ovs_add_bidir_meter_rules
    title "Testing meter on REPs"
    local t=4
    ovs_send_scapy_packets $VF1 $VF2 $NS0_IP $NS1_IP $t 100 ns0 ns1
    check_dpdk_offloads $NS0_IP
    ovs-ofctl -O OpenFlow13 meter-stats br-phy
    ovs_check_tcpdump $((rate*t+10))
    ovs_del_meter br-phy 1
    ovs_del_meter br-phy 2
}

test_pre_config
run
trap - EXIT
cleanup_test
test_done
