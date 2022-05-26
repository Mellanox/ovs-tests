#!/bin/bash
#
# Test OVS-DPDK ICMPv6 with header modify
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

IP6_ADDR1="10:0:1::1"
IP6_ADDR2="10:0:1::2"
DUMMY_IP6_ADDR="10:0:1::3"

function config() {
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    ovs_conf_set hw-offload false
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP $IP6_ADDR1
    config_ns ns1 $VF2 $REMOTE_IP $IP6_ADDR2
    config_static_ipv6_neigh_ns ns1 ns0 $VF2 $VF $DUMMY_IP6_ADDR
    config_static_ipv6_neigh_ns ns1 ns0 $VF2 $VF $IP6_ADDR2
    config_static_ipv6_neigh_ns ns0 ns1 $VF $VF2 $IP6_ADDR1
}

function run() {
    config
    ovs_wait_until_ipv6_done $IP6_ADDR2 ns0
    ovs_add_ipv6_mod_hdr_rules $IP6_ADDR1 $IP6_ADDR2 $DUMMY_IP6_ADDR

    # icmp
    verify_ping $DUMMY_IP6_ADDR ns0 1700
}

run
ovs_conf_set hw-offload true
start_clean_openvswitch
test_done
