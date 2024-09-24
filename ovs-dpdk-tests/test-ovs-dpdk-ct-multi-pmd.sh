#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT and OVS configured with multi PMD
#
# Require external server
#
# Bug SW #4069266: [OVS-DOCA, Performance] Failed to insert DOCA-CT entry: -24 when sending 20 mpps rate with packet size 114 and ct connections
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    ovs-vsctl --no-wait remove o . other_config pmd-cpu-mask
    ovs-vsctl --no-wait remove o . other_config hw-offload-ct-size
    ovs-vsctl --no-wait remove o . other_config doca-ct
    ovs-vsctl --no-wait remove o . other_config doca-ct-ipv6
    cleanup_test
}

function config() {
    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $LOCAL_IP
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:doca-ct=true
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:doca-ct-ipv6=false
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:pmd-cpu-mask=0x6
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:hw-offload-ct-size=4096
    restart_openvswitch_nocheck
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function run() {
    config
    config_remote_nic
    add_openflow_rules

    verify_ping

    title "Run traffic and try to fill ct table entirely"
    set_iperf2
    generate_traffic "remote" $LOCAL_IP none true ns0 local 30 4096

    verify_ovs_readd_port br-phy
}

run

check_counters

trap - EXIT
cleanup
test_done
