#!/bin/bash
#
# Verify adding vxlan encap/decap rules does not use local route which results
# in rule not in hw. In newer kernel the driver has fixes to use vxlan device
# hint if available:
#
# 2f8ec867b6c3 net/mlx5e: Specify out ifindex when looking up encap route
# 819c319c8c91 net/mlx5e: Specify out ifindex when looking up decap route
#
# Feature #2619265: [Alibaba-RoCE] local and remote VTEPs are in the same host for vxlan

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs

local_ip="39.0.10.60"
remote_ip="39.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=4789
id=98


function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
    reset_tc $NIC
}

function config_vxlan() {
    local extra=$1
    echo "config vxlan $extra"
    ip link add vxlan1 type vxlan id $id $extra dstport $dst_port
    ip link set vxlan1 up
    ifconfig $NIC $local_ip/24 up
}

function add_rules() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    reset_tc $NIC $REP vxlan1

    # tunnel key set
    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac \
        action tunnel_key set \
        id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
    if [ "$use_hint" == "true" ]; then
        verify_in_hw $REP 1
    else
        verify_not_in_hw $REP 1
    fi

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 2 flower \
        enc_src_ip $remote_ip           \
        enc_dst_ip $local_ip            \
        enc_dst_port $dst_port          \
        enc_key_id $id                  \
        action tunnel_key unset pipe    \
        action mirred egress redirect dev $REP
    if [ "$use_hint" == "true" ]; then
        verify_in_hw vxlan1 2
    else
        verify_not_in_hw vxlan1 2
    fi
}

function test_add_rule_neigh_local() {
    ifconfig $NIC up
    local mac2=`cat /sys/class/net/$NIC2/address`
    ifconfig $NIC2 $remote_ip/24 up
    ip r show dev $NIC
    ip n show $remote_ip
    add_rules $local_ip $remote_ip
    ifconfig $NIC2 0
    reset_tc $REP
}

function do_test() {
    title "$1 hint $use_hint"
    eval $1
}

cleanup
use_hint="false"
config_vxlan
do_test test_add_rule_neigh_local

cleanup
use_hint="true"
config_vxlan "dev $NIC"
do_test test_add_rule_neigh_local

cleanup
test_done
