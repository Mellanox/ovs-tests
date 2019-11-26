#!/bin/bash
#
# Test insert vxlan rule with duplicated encap entries
# Bug SW #1975177: [Upstream CX5] Neigh update of non-valid duplicated encap entry cause kernel panic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev_if_no_rep $REP
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

mac2="e4:11:22:11:77:77"

function cleanup() {
    ip -all netns delete
    reset_tc $REP
}
trap cleanup EXIT

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function run() {
    local ip_src=$1
    local ip_dst=$2

    ip -all netns delete
    title "Test duplicated encap entries"
    config_vf ns0 $VF $REP $IP1
    echo "ip netns exec ns0 ip neigh add $IP2 lladdr $mac2 dev $VF"

    title " - create vxlan interface"
    vx=vxlan1
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up

    ip a show dev $vx

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC

    TUNNEL_KEY_SET="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    echo "add vf mirror rules"
    tc filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        $TUNNEL_KEY_SET pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET pipe \
        action mirred egress redirect dev $vx && err || success
}

run 20.12.11.1 20.12.12.1

test_done
