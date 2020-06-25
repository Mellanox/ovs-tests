#!/bin/bash
#
# Test verifies that indirect block is properly unbound when unloading mlx5.
# Uses vlxan device.
#
# Bug SW #2215041: Crash in TC while calling indirect device offload cb after removing mlx5 module
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev

VXLAN=vxlan1
local_ip="192.168.1.1"
remote_ip="192.168.1.2"
dst_port=4789
id=98
VM_DST_MAC=e4:11:22:33:44:70

function cleanup() {
    load_modules
    ip a flush dev $NIC
    ip l del dev $VXLAN
}
trap cleanup EXIT

function config_vxlan() {
    title "config vxlan dev"

    ip link add $VXLAN type vxlan dstport $dst_port external
    ip addr add ${local_ip}/24 dev $NIC
    ip link set $VXLAN up
    ip link set up dev $NIC
    tc qdisc add dev $VXLAN ingress
}

function add_vxlan_rule() {
    title "local_ip $local_ip remote_ip $remote_ip"

    reset_tc $NIC $REP $VXLAN

    tc_filter add dev $VXLAN protocol ip parent ffff: prio 10\
              flower enc_src_ip $remote_ip enc_dst_ip $local_ip \
              enc_key_id $id enc_dst_port $dst_port src_mac $VM_DST_MAC \
              action tunnel_key unset \
              action mirred egress redirect dev $REP || err "Failed to add rule"
}

config_vxlan
add_vxlan_rule
tc -s filter show dev $VXLAN ingress

title "Unload modules"
unload_modules

title "Try to access filter again"
tc -s filter show dev $VXLAN ingress && success || err "Failed to print filters"

cleanup
trap - EXIT
test_done
