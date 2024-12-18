#!/bin/bash
#
# Test adding/removing VFs with hw-offload false
#
# [OVS] Bug SW #3574655: [OVS-DOCA] DPDK fails initialize SF port and allocate memory
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
enable_switchdev
bind_vfs

function cleanup() {
    ovs_conf_set hw-offload true
    cleanup_test
}

trap cleanup EXIT

function config() {
    ovs_conf_set hw-offload false
    cleanup_test
    ovs_add_bridge
    ovs_add_port "PF"

    ovs_add_port "VF" 0
    ovs_del_port "VF" 0

    ovs_add_port "VF" 0
    ovs_add_port "VF" 1

    config_ns ns0 $VF $LOCAL_IP
    config_ns ns1 $VF2 $REMOTE_IP
    ovs-vsctl show
}

function run() {
    config

    verify_ping
}

run
trap - EXIT
cleanup
test_done
