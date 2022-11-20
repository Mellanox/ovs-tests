#!/bin/bash
#
# Test insert vxlan rule with multiple encap entries
#
# Bug SW #3228357: Kernel crash: RIP: 0010:mlx5_flow_dests_cmp+0x77/0x90 [mlx5_core]

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

function test_tunnel() {
    local ip_src="20.12.11.1"
    local ip_dst="20.12.12.1"
    local ip_dst2="20.12.13.1"

    title "Test multi encap entries"

    title "- create vxlan interface"
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up

    ip a show dev $vx

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip link set dev $NIC up

    # validate only one encap entry
    ip n r $ip_dst dev $NIC lladdr e4:11:f6:25:a5:99

    TUNNEL_KEY_SET="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    # not validated encap
    TUNNEL_KEY_SET2="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst2
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    title "add rule"
    reset_tc $REP

    # not validated encap is first.
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        $TUNNEL_KEY_SET2 pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET pipe \
        action mirred egress redirect dev $vx

    ip n
    # look for neigh entries, even if incomplete. to know the rule add started a neigh lookup.
    ip n | grep -q $ip_dst || err "Cannot find $ip_dst neigh entry"
    ip n | grep -q $ip_dst2 || err "Cannot find $ip_dst2 neigh entry"

    reset_tc $REP
    ip n del $ip_dst dev $NIC
    ip n del $ip_dst2 dev $NIC
}


test_tunnel
test_done
