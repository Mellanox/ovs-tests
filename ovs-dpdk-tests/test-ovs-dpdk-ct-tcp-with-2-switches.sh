#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT on two bridges
# each with a different esw manager.
#
# Requires external server.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev
enable_switchdev $NIC2
require_interfaces REP NIC NIC2
unbind_vfs
bind_vfs
unbind_vfs $NIC2
bind_vfs $NIC2

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 1 true "br-phy" $NIC &
    config_simple_bridge_with_rep 1 true "br-phy-2" $NIC2 &
    wait
    config_ns ns0 $VF $LOCAL_IP
    config_ns ns0 `get_vf 0 $NIC2` $LOCAL_IP2
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip a flush dev $REMOTE_NIC2
               ip a add $REMOTE_IP2/24 dev $REMOTE_NIC2
               ip l set dev $REMOTE_NIC2 up"
}

function run() {
    config
    config_remote
    ovs_add_ct_rules "br-phy" tcp
    ovs_add_ct_rules "br-phy-2" tcp

    verify_ping $REMOTE_IP
    verify_ping $REMOTE_IP2

    generate_traffic "remote" $LOCAL_IP
    generate_traffic "remote" $LOCAL_IP2

    set_iperf2
    generate_traffic "remote" $LOCAL_IP
    generate_traffic "remote" $LOCAL_IP2
}

run
check_counters
trap - EXIT
cleanup_test
test_done
