#!/bin/bash
#
# Test insert vxlan rule with duplicated encap entries
# Bug SW #1975177: [Upstream CX5] Neigh update of non-valid duplicated encap entry cause kernel panic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
require_interfaces REP

mac2="e4:11:22:11:77:77"
vx=vxlan1
vxlan_port=4789

function cleanup() {
    ip link del $vx &>/dev/null
    reset_tc $REP
}
trap cleanup EXIT

function test_duplicate_tunnel() {
    local ip_src=$1
    local ip_dst=$2

    title "Test duplicated encap entries"

    title "- create vxlan interface"
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

    title "- add dup encap rule and expect to fail"
    reset_tc $REP
    tc filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        $TUNNEL_KEY_SET pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET pipe \
        action mirred egress redirect dev $vx && err || success
}


test_duplicate_tunnel 20.12.11.1 20.12.12.1
test_done
