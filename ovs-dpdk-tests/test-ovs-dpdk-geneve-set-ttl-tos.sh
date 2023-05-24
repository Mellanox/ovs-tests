#!/bin/bash
#
# Test OVS with geneve traffic with setting encap ttl and tos values
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
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "geneve"
    ovs-vsctl set interface geneve0 options:ttl=22 options:tos=0x24
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    ovs-vsctl show
}

function config_remote() {
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip link add $TUNNEL_DEV type geneve id $TUNNEL_ID remote $LOCAL_TUN_IP dstport 6081
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $TUNNEL_DEV
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
}

function run() {
    config
    config_remote

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
