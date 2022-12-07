#!/bin/bash
#
# Test vxlan neigh update with multiple encaps
#
# Invalid multiple encaps and validate them again.
# Bug was first invalidate encap caused skip clearing the other
# invalidated encaps from a flow and reusing those invalid encap
# and first encap validated again.
#
# Bug SW #3271508: deadlock with multiple encapsulations
# Bug SW #3277131: [Upstream] Timeout adding rule with multiple encapsulations

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
require_interfaces REP

mac2="e4:11:22:11:77:77"
vx=vxlan1
vxlan_port=4789
iterations=100

function cleanup() {
    ip link del $vx &>/dev/null
    reset_tc $REP
}
trap cleanup EXIT

function neigh_update() {
    ip n d $ip_dst2 dev $NIC
    ip n d $ip_dst3 dev $NIC
    ip n d $ip_dst4 dev $NIC
    sleep 0.1
    ip n r $ip_dst2 dev $NIC lladdr e4:11:f6:25:a5:87
    ip n r $ip_dst3 dev $NIC lladdr e4:11:f6:25:a5:88
    ip n r $ip_dst4 dev $NIC lladdr e4:11:f6:25:a5:89
}

function test_tunnel() {
    local ip_src="20.12.11.1"
    local ip_dst="20.12.12.1"
    ip_dst2="20.12.13.1"
    ip_dst3="20.12.14.1"
    ip_dst4="20.12.15.1"

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
    reset_tc $REP

    # validate the encaps
    ip n r $ip_dst dev $NIC lladdr e4:11:f6:25:a5:99
    ip n r $ip_dst2 dev $NIC lladdr e4:11:f6:25:a5:87
    ip n r $ip_dst3 dev $NIC lladdr e4:11:f6:25:a5:88
    ip n r $ip_dst4 dev $NIC lladdr e4:11:f6:25:a5:89

    TUNNEL_KEY_SET="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    TUNNEL_KEY_SET2="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst2
        dst_port 4789
        id 102
        ttl 64
        nocsum"
    TUNNEL_KEY_SET3="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst3
        dst_port 4789
        id 102
        ttl 64
        nocsum"
    TUNNEL_KEY_SET4="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst4
        dst_port 4789
        id 102
        ttl 64
        nocsum"


    title "start add/del rule"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        $TUNNEL_KEY_SET2 pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET3 pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET4 pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET pipe \
        action mirred egress redirect dev $vx

    log "do neigh update"
    neigh_update

    sleep 2
    reset_tc $REP
    ip n del $ip_dst dev $NIC
    ip n del $ip_dst2 dev $NIC
    ip n del $ip_dst3 dev $NIC
    ip n del $ip_dst4 dev $NIC
}


test_tunnel
test_done
