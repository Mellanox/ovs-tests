#!/bin/bash
#
# Test OVS-DPDK with vxlan traffic with multiple CT zones
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test

    config_tunnel "vxlan"
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-int
    local zone1=$RANDOM
    local zone2=$RANDOM
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "icmp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0,tcp,ct_state=-trk, actions=ct(zone=$zone1, table=1)"
    ovs-ofctl add-flow br-int "table=1,tcp,ct_state=+trk+new, actions=ct(zone=$zone1, commit, table=2)"
    ovs-ofctl add-flow br-int "table=1,ct_zone=$zone1,tcp,ct_state=+trk+est, actions=ct(zone=$zone2, table=2)"
    ovs-ofctl add-flow br-int "table=2,tcp,ct_state=+trk+new, actions=ct(zone=$zone2, commit),normal"
    ovs-ofctl add-flow br-int "table=2,ct_zone=$zone2,tcp,ct_state=+trk+est, actions=normal"
    ovs-ofctl dump-flows br-int --color
}

function print_ovs_memzone_count() {
    title "Verify ovs no memzone leak"
    local memzone_count=`ovs-appctl dpdk/get-memzone-stats | grep ^Zone | wc -l`
    echo "memzone count: $memzone_count"
}

function run() {
    config
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP

    ovs_flush_rules
    print_ovs_memzone_count

    verify_ovs_readd_port br-int
}

run
trap - EXIT
cleanup_test
test_done
