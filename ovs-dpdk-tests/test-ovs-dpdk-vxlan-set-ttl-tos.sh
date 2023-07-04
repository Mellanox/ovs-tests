#!/bin/bash
#
# Test OVS with vxlan traffic with setting encap ttl and tos values
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

trap cleanup_test EXIT

function config() {
    cleanup_test
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "vxlan"
    ovs-vsctl set interface vxlan_br-int options:ttl=22 options:tos=0x24
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_remote_tunnel "vxlan"
    ovs-vsctl show
}

function run() {
    config

    on_remote "timeout 3 tcpdump -qnnei $REMOTE_NIC -c 10 \"ip and ip[8]=22 and ip[1]=0x24\" -vvv -Q in" &
    pid_remote=$!
    sleep 2
    # icmp
    verify_ping $REMOTE_IP ns0

    title "Verify traffic on remote"
    verify_have_traffic $pid_remote
}

run
start_clean_openvswitch
trap - EXIT
cleanup_test
test_done
