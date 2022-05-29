#!/bin/bash
#
# Test OVS-DPDK with ct-nat + frags
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

DUMMY_IP_ADDR="1.1.1.111"

function config() {
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    ovs_conf_set hw-offload false
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    config_static_arp_ns ns1 ns0 $VF2 $DUMMY_IP_ADDR
    config_static_arp_ns ns1 ns0 $VF2 $REMOTE_IP
    config_static_arp_ns ns0 ns1 $VF $LOCAL_IP
}

function run() {
    config
    ovs_add_ct_dnat_rules "rep0" "rep1" $REMOTE_IP "ip"

    # icmp
    verify_ping $DUMMY_IP_ADDR ns0 1700
}

run
ovs_conf_set hw-offload true
start_clean_openvswitch
test_done
