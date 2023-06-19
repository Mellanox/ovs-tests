#!/bin/bash
#
# Test OVS-DPDK with vxlan TCP traffic with CT
# with label larger than 32 bits
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap test_cleanup_local EXIT

function test_cleanup_local() {
    cleanup_test
    ovs_conf_remove ct-labels-mapping
}

function config() {
    cleanup_test
    debug "Restarting OVS"
    ovs_conf_set ct-labels-mapping true
    start_clean_openvswitch

    config_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function config_remote() {
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip link add $TUNNEL_DEV type vxlan id $TUNNEL_ID remote $LOCAL_TUN_IP dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $TUNNEL_DEV
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "icmp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0,tcp,ct_state=-trk,actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,tcp,ct_state=+trk+new,actions=ct(commit, exec(set_field:0x1234567891/0xffffffffff->ct_label)),normal"
    ovs-ofctl add-flow br-int "table=1,tcp,ct_state=+trk+est,ct_label=0x1234567891/0xffffffffff,actions=normal"
    debug "OVS flow rules:"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    verify_ping
    generate_traffic "remote" $LOCAL_IP
}

run
start_clean_openvswitch
test_done
