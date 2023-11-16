#!/bin/bash
#
# Test OVS-DPDK for rules getting stuck
#
# Bug SW #3651970: Stuck rule in hw
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $LOCAL_IP
}

function run() {
    config
    config_remote_nic

    title "Run stress traffic durnig ovs max-idle=1"
    ovs_conf_set max-idle 1
    for i in `seq 30`; do
        verify_ping || break
        ovs-appctl dpctl/dump-flows
    done
    ovs_conf_remove max-idle
    fail_if_err

    title "Run traffic again with default max-idle"
    for i in `seq 3`; do verify_ping; done

    title "Check datapath rules"
    ovs-appctl dpctl/dump-flows | grep 0800
    if [ `ovs-appctl dpctl/dump-flows | grep 0800 | wc -l` -lt 2 ]; then
        err "Datapath rules are missing"
    fi

    ovs_clear_bridges
    config_sriov 2
}

run

check_counters

trap - EXIT
cleanup_test
test_done
