#!/bin/bash
#
# Test OVS with dpctl rule from vxlan to another vxlan.
#
# ufid:fd2bc8e0-1470-4b50-b60d-b028b2b38db0,
# skb_priority(0/0),tunnel(tun_id=0x65,src=10.10.11.3,dst=10.10.11.2,ttl=0/0,tp_dst=4789,flags(+key)),skb_mark(0/0),ct_state(0/0),ct_zone(0/0),ct_mark(0/0),ct_label(0/0),recirc_id(0),dp_hash(0/0),in_port(vxlan_sys_4789),packet_type(ns=0/0,id=0/0),eth(src=00:00:00:00:00:00/00:00:00:00:00:00,dst=fa:16:3e:2a:4e:23),eth_type(0x0800),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0x3,ttl=0/0,frag=no),
# packets:543, bytes:45612, used:0.430s, dp:tc,
# actions:set(tunnel(tun_id=0x66,src=10.10.12.2,dst=10.10.12.3,tp_dst=4789,flags(key))),vxlan_sys_4789
#
# The TC rule was created with actions encap,decap,mirred instead of decap,encap,mirred.
#
# Bug SW #2874200: Incorrect TC flow generated for the decap+encap OVS datapath flow

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_TUN=7.7.7.8
VXLAN_ID=42
LOCAL_TUN2=7.7.8.7
REMOTE_TUN2=7.7.8.8

config_sriov 2
enable_switchdev
require_interfaces REP NIC

dump_sleep=":"

function add_flow_dump_tc() {
    local flow=$1
    local actions=$2
    local dev=$3
    local cmd="ovs-appctl dpctl/add-flow \"$flow\" \"$actions\" ; $dump_sleep ; tc filter show dev $dev ingress"
    local m=`eval $cmd`

    [ -z "$m" ] && m=`eval $cmd`

    if [ -z "$m" ]; then
        err "Failed to add test flow: $flow"
        return 1
    fi

    output=$m
    return 0
}

function cleanup() {
    ovs_clear_bridges &>/dev/null
    reset_tc $REP
}
trap cleanup EXIT

function run() {
    cleanup

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_TUN options:key=$VXLAN_ID options:dst_port=4789
    ovs-vsctl add-port br-ovs vxlan2 -- set interface vxlan2 type=vxlan options:local_ip=$LOCAL_TUN2 options:remote_ip=$REMOTE_TUN2 options:key=$VXLAN_ID options:dst_port=4789

    local filter="ufid:c5f9a0b1-3399-4436-b742-30825c64a1e5,recirc_id(0),in_port(2),eth_type(0x0800),eth(src=00:00:00:00:00:00/00:00:00:00:00:00,dst=fa:16:3e:2a:4e:23),tunnel(tun_id=0x65,src=10.10.11.3,dst=10.10.11.2,ttl=0/0,tp_dst=4789,flags(+key)),ipv4(src=0.0.0.0/0.0.0.0,dst=0.0.0.0/0.0.0.0,proto=0/0,tos=0/0x3,ttl=0/0,frag=no)"
    local actions="set(tunnel(tun_id=0x66,src=10.10.12.2,dst=10.10.12.3,tp_dst=4789,flags(key))),2"

    title "Add dpctl flow"
    add_flow_dump_tc $filter $actions vxlan_sys_4789
    local rc=$?

    if [ $rc -ne 0 ]; then
        return
    fi

    title "Verify TC rule"
    echo -e $output

    echo $output | grep -q "tunnel_key *unset.*tunnel_key *set"
    if [ $? -eq 0 ]; then
        success
        return
    fi

    echo $output | grep -q "tunnel_key *set.*tunnel_key *unset"
    if [ $? -eq 0 ]; then
        err "decap action after encap action. expected decap before encap."
        return
    fi

    err "Failed matching"
}

run
test_done
