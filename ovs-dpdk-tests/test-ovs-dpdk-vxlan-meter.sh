#!/bin/bash
#
# Test OVS-DPDK openflow meters with VxLAN traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

trap cleanup_test EXIT

#Test pre-req
function test_pre_config() {
    require_remote_server
    config_sriov 2
    enable_switchdev
    bind_vfs
    cleanup_test
}

function config_topology() {
    config_tunnel vxlan 2
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_remote_tunnel vxlan
}

function run() {
    config_topology

    title "Testing meter on PF"
    ovs_add_meter br-phy 1 pktps 3
    ovs_add_simple_meter_rule
    send_metered_ping
    check_dpdk_offloads $LOCAL_IP
    ovs_del_meter
    ovs-appctl revalidator/purge

    debug "Testing meter on REP"
    ovs_add_meter br-int 1 pktps 50
    ovs_add_simple_meter_rule br-int 1
    send_metered_ping ns0 200 5 $REMOTE_IP 0.01 115
    check_dpdk_offloads $LOCAL_IP
    ovs_del_meter br-int 1
}

test_pre_config
run
trap - EXIT
cleanup_test
test_done
